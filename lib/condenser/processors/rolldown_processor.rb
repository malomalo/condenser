# frozen_string_literal: true

require 'json'
require 'socket'

class Condenser::RolldownProcessor

  SCRIPT = File.expand_path('rolldown_processor.js', __dir__)
  DYNAMIC_IMPORTS = %i[inline keep].freeze
  MAX_BUILDS = 100
  MAX_MEMORY = 1536 * 1024 * 1024

  class WorkerDied < RuntimeError; end

  @@setup = []

  def self.install_npm_packages(npm_path)
    return if @@setup.include?(npm_path)

    ::Condenser::NodeProcessor.new(npm_path).npm_install('rolldown')
    @@setup << npm_path
  end

  def self.call(environment, input)
    new(environment.npm_path).call(environment, input)
  end

  def self.stop_workers
    Worker.stop_all
  end

  def self.read_version(bundler_path)
    package = File.join(bundler_path, 'package.json')
    JSON.parse(File.read(package))['version'] if File.exist?(package)
  end

  def name
    self.class.name
  end

  def options
    options = {prefix: @prefix, dynamic_imports: @dynamic_imports, aliases: @aliases, rolldown: rolldown_version}
    options[:platform] = @platform if @platform != 'neutral'
    options
  end

  def rolldown_version
    @rolldown_version ||= begin
      path = @bundler_path || (@npm_dir && File.join(@npm_dir, 'node_modules', 'rolldown'))
      self.class.read_version(path) if path
    end
  end

  def initialize(dir = nil, prefix: nil, dynamic_imports: :inline, bundler_path: nil, aliases: {}, platform: 'neutral', max_builds: MAX_BUILDS, max_memory: MAX_MEMORY)
    unless DYNAMIC_IMPORTS.include?(dynamic_imports)
      raise ArgumentError, "dynamic_imports must be :inline or :keep, got #{dynamic_imports.inspect}"
    end
    self.class.install_npm_packages(dir) if bundler_path.nil? && dir
    @npm_dir = dir
    @prefix = prefix
    @dynamic_imports = dynamic_imports
    @bundler_path = bundler_path
    @aliases = aliases
    @platform = platform
    @max_builds = max_builds
    @max_memory = max_memory
  end

  def call(environment, input)
    Runner.new(@npm_dir, prefix: @prefix, dynamic_imports: @dynamic_imports, bundler_path: @bundler_path, aliases: @aliases, platform: @platform, max_builds: @max_builds, max_memory: @max_memory).call(environment, input)
  end

  # A node process with Rolldown loaded that runs one build at a time.
  # Workers are shared by every RolldownProcessor in the process, one per
  # node binary and Rolldown install (and per nesting level, so an export
  # started while answering a build gets its own).
  class Worker
    @workers = {}
    @owner = Process.pid
    @lock = Mutex.new

    class << self
      def checkout(binary, bundler_path)
        depth = Thread.current[:condenser_rolldown_depth] || 0
        worker = @lock.synchronize do
          reset_after_fork
          @workers[[binary, bundler_path, depth]] ||= new(binary, bundler_path)
        end
        Thread.current[:condenser_rolldown_depth] = depth + 1
        yield worker
      ensure
        Thread.current[:condenser_rolldown_depth] = depth
      end

      def workers
        @lock.synchronize do
          reset_after_fork
          @workers.values
        end
      end

      def stop_all
        workers.each(&:stop)
      end

      private

      def reset_after_fork
        return if @owner == Process.pid

        @workers.each_value(&:abandon)
        @workers = {}
        @owner = Process.pid
      end
    end

    at_exit { stop_all }

    attr_reader :pid

    def initialize(binary, bundler_path)
      @binary = binary
      @bundler_path = bundler_path
      @lock = Mutex.new
      @next_build = 0
    end

    # Yields each hook request as (method, args) and returns the build's
    # 'done' or 'error' message. An exception from the block is re-raised
    # once the build has finished.
    def build(config, logger:, max_builds:, max_memory:)
      @lock.synchronize do
        start if @pid.nil? || @version != Condenser::RolldownProcessor.read_version(@bundler_path)
        io = @io
        id = (@next_build += 1)
        finished = false
        failure = nil

        begin
          write(io, { build: id, config: config })
          while (line = io.gets)
            break unless line.end_with?("\n")

            message = JSON.parse(line)
            if message.key?('rid')
              if message['build'] != id
                write(io, { rid: message['rid'], error: 'stale build' })
                next
              end

              begin
                write(io, { rid: message['rid'], return: yield(message['method'], message['args']) })
              rescue StandardError, ScriptError => e
                failure ||= e
                write(io, { rid: message['rid'], error: "#{e.class}: #{e.message}" })
              end
            elsif message['build'] == id
              case message['method']
              when 'warn'
                logger.warn(message['args'][0])
              when 'done', 'error'
                finished = true
                @builds += 1
                @rss = message['rss']
                raise failure if failure
                return message
              end
            end
          end
          raise WorkerDied, "rolldown exited with #{kill}"
        rescue Errno::EPIPE, Errno::ECONNRESET, IOError
          raise WorkerDied, "rolldown exited with #{kill}"
        ensure
          if !finished
            kill
          elsif @builds >= max_builds || @rss.to_i > max_memory
            stop
          end
        end
      end
    end

    def stop
      io, pid = @io, @pid
      @io = @pid = nil
      return unless pid

      io.close rescue nil
      reap(pid)
    end

    def kill
      Process.kill('TERM', @pid) rescue nil if @pid
      stop
    end

    def abandon
      @io&.close rescue nil
      @io = @pid = nil
    end

    private

    def start
      stop
      io, child_io = UNIXSocket.pair
      begin
        @pid = Process.spawn(@binary, '--max_old_space_size=5120', SCRIPT, @bundler_path, in: File::NULL, 3 => child_io)
      rescue Exception
        io.close
        raise
      ensure
        child_io.close
      end
      @io = io
      @version = Condenser::RolldownProcessor.read_version(@bundler_path)
      @builds = 0
      @rss = nil
    end

    def write(io, message)
      io.write(JSON.generate(message), "\n")
    end

    def reap(pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      until (_, status = Process.wait2(pid, Process::WNOHANG))
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          Process.kill('KILL', pid)
          return Process.wait2(pid)[1]
        end
        sleep 0.005
      end
      status
    rescue Errno::ECHILD, Errno::ESRCH
      nil
    end
  end

  class Runner < Condenser::NodeProcessor
    def initialize(dir = nil, prefix: nil, dynamic_imports: :inline, bundler_path: nil, aliases: {}, platform: 'neutral', max_builds: MAX_BUILDS, max_memory: MAX_MEMORY)
      super(dir)
      @prefix = prefix
      @dynamic_imports = dynamic_imports
      @aliases = aliases
      @platform = platform
      @max_builds = max_builds
      @max_memory = max_memory
      @bundler_path = bundler_path || (dir && npm_module_path('rolldown')) || 'rolldown'
    end

    def call(environment, input)
      @environment = environment
      @input = input
      @accept = input[:content_types].last
      @entry = input[:source_file]

      config = {
        entry: @entry,
        bundlerPath: @bundler_path,
        cwd: environment.base || Dir.pwd,
        modules: npm_path ? [npm_module_path] : [],
        aliases: @aliases,
        platform: @platform
      }

      input[:source] = exec_runtime(config)
      input[:type] = 'module'
      input
    end

    def exec_runtime(config)
      attempts = 0
      message = begin
        Worker.checkout(binary, @bundler_path) do |worker|
          worker.build(config, logger: @environment.logger, max_builds: @max_builds, max_memory: @max_memory) do |method, args|
            answer(method, *args)
          end
        end
      rescue WorkerDied => e
        retry if (attempts += 1) == 1
        raise exec_runtime_error(e.message)
      end

      if message['method'] == 'error'
        error = message['args']
        raise exec_runtime_error("#{error[0]}: #{error[1]}")
      end
      message['args'][0]
    end

    private

    def answer(method, *args)
      case method
      when 'resolve'
        importee, importer = args
        # npm: false; Rolldown resolves node_modules when this is nil.
        @environment.find(importee, importer, accept: @accept)&.source_file
      when 'load'
        id = args.first
        if id == @entry
          { code: utf8(@input[:source]), map: @input[:map] }
        elsif (asset = @environment.find(id, accept: @accept))
          { code: utf8(asset.source), map: asset.sourcemap }
        end
      when 'glob'
        glob_module(args.first)
      when 'resolveDynamicImport'
        resolve_dynamic_import(*args)
      end
    end

    def utf8(string)
      string.encoding == Encoding::BINARY ? string.dup.force_encoding(Encoding::UTF_8) : string
    end

    def glob_module(glob)
      code = String.new
      exports = []
      @environment.resolve(glob, nil, accept: @accept, npm: true).each_with_index do |f, i|
        if f.has_default_export?
          code << "import _#{i} from #{JSON.generate(f.source_file)};\n"
          exports << "_#{i}"
        elsif f.has_exports?
          code << "import * as _#{i} from #{JSON.generate(f.source_file)};\n"
          exports << "_#{i}"
        else
          code << "import #{JSON.generate(f.source_file)};\n"
        end
      end
      code << "export default [#{exports.join(', ')}];"
    end

    def resolve_dynamic_import(importee, importer)
      asset = @environment.find(importee, importer, accept: @accept, npm: true)
      asset ||= @environment.find(importee.delete_suffix('.js') + "/index.js", importer, accept: @accept, npm: true)
      asset ||= @environment.find(importee.gsub(/\/[^\/]+$/, '') + "/dist/index.js", importer, accept: @accept, npm: true)
      return if asset.nil?

      if asset.source_file == @input[:source_file]
        { id: @entry }
      elsif @dynamic_imports == :keep
        { external: true, path: File.join("/", *[@prefix, asset.path].compact) }
      else
        { id: asset.source_file }
      end
    end
  end
end
