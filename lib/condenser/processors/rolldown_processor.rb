# frozen_string_literal: true

require 'json'
require 'socket'

class Condenser::RolldownProcessor

  SCRIPT = File.expand_path('rolldown_processor.js', __dir__)
  DYNAMIC_IMPORTS = %i[inline keep].freeze
  MAX_MEMORY = 1536 * 1024 * 1024

  class WorkerDied < RuntimeError; end

  @@setup = []

  def self.install_npm_packages(npm_path)
    return if @@setup.include?(npm_path)

    ::Condenser::NodeProcessor.new(npm_path).npm_install('rolldown')
    @@setup << npm_path
  end

  def self.stop_workers
    Worker.stop_all
  end

  def self.read_version(bundler_path)
    JSON.parse(File.read(File.join(bundler_path, 'package.json')))['version']
  rescue Errno::ENOENT
    nil
  end

  def name
    self.class.name
  end

  def options
    options = {prefix: @prefix, dynamic_imports: @dynamic_imports, aliases: @aliases, rolldown: @rolldown_version}
    options[:platform] = @platform if @platform != 'neutral'
    options
  end

  def initialize(dir = nil, prefix: nil, dynamic_imports: :inline, bundler_path: nil, aliases: {}, platform: 'neutral', max_memory: MAX_MEMORY)
    unless DYNAMIC_IMPORTS.include?(dynamic_imports)
      raise ArgumentError, "dynamic_imports must be :inline or :keep, got #{dynamic_imports.inspect}"
    end
    unless max_memory.is_a?(Integer) && max_memory.positive?
      raise ArgumentError, "max_memory must be a positive Integer, got #{max_memory.inspect}"
    end
    self.class.install_npm_packages(dir) if bundler_path.nil? && dir
    @npm_dir = dir
    @prefix = prefix
    @dynamic_imports = dynamic_imports
    @bundler_path = bundler_path
    @aliases = aliases
    @platform = platform
    @max_memory = max_memory
    @lock = Mutex.new
    @rolldown_version = self.class.read_version(rolldown_path) if bundler_path || dir
  end

  def call(environment, input)
    Runner.new(@npm_dir, worker: worker, prefix: @prefix, dynamic_imports: @dynamic_imports, aliases: @aliases, platform: @platform).call(environment, input)
  end

  def worker
    @lock.synchronize do
      @worker ||= Worker.new(
        Condenser::NodeProcessor.new(@npm_dir).binary,
        rolldown_path,
        max_memory: @max_memory
      )
    end
  end

  def rolldown_path
    @bundler_path || (@npm_dir ? File.join(@npm_dir, 'node_modules', 'rolldown') : 'rolldown')
  end

  # A node process with Rolldown loaded that runs one build at a time.
  class Worker
    @workers = ObjectSpace::WeakMap.new

    def self.stop_all
      @workers.each_key(&:stop)
    end

    def self.track(worker)
      @workers[worker] = true
    end

    at_exit { stop_all }

    attr_reader :pid

    def initialize(binary, bundler_path, max_memory: MAX_MEMORY)
      @binary = binary
      @bundler_path = bundler_path
      @max_memory = max_memory
      @lock = Mutex.new
      @next_build = 0
      self.class.track(self)
    end

    # Yields each hook request as (method, args) and returns the build's
    # 'done' or 'error' message. An exception from the block is re-raised
    # once the build has finished or the worker has died.
    def build(config, logger:, &block)
      return throwaway_build(config, logger: logger, &block) if @lock.owned?

      @lock.synchronize do
        start if @pid.nil? || @owner != Process.pid
        id = (@next_build += 1)
        @failure = nil
        message = nil

        begin
          write({ build: id, config: config })
          while (line = @io.gets)&.end_with?("\n")
            break if (message = receive(JSON.parse(line), id, logger, &block))
          end
        rescue Errno::EPIPE, Errno::ECONNRESET, IOError
          nil
        end
        raise @failure if @failure
        raise WorkerDied, exited unless message

        message
      ensure
        terminate if !message || message['rss'].to_i > @max_memory
      end
    end

    def stop
      @stopping = true
      @lock.synchronize { terminate }
    end

    def stopping?
      @stopping
    end

    private

    # Answers a hook request or logs a warning, and returns this build's
    # 'done' or 'error' message.
    def receive(message, id, logger, &block)
      if message.key?('rid')
        write({ rid: message['rid'], **reply(message, id, &block) })
      elsif message['build'] == id
        case message['method']
        when 'warn' then logger.warn(message['args'][0])
        when 'done', 'error' then return message
        end
      end
      nil
    end

    def reply(message, id)
      return { error: 'stale build' } if message['build'] != id

      { return: yield(message['method'], message['args']) }
    rescue StandardError, ScriptError => e
      @failure ||= e
      { error: "#{e.class}: #{e.message}" }
    end

    def exited
      "rolldown exited with #{terminate || 'an unknown status'}"
    end

    def throwaway_build(config, logger:, &block)
      worker = Worker.new(@binary, @bundler_path)
      worker.build(config, logger: logger, &block)
    ensure
      worker.stop
    end

    def start
      terminate
      @stopping = false
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
      @owner = Process.pid
    end

    def terminate
      io, pid = @io, @pid
      @io = @pid = nil
      io&.close
      reap(pid) if pid && @owner == Process.pid
    end

    def write(message)
      @io.write(JSON.generate(message), "\n")
    end

    def reap(pid)
      Process.kill('TERM', pid)
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
    def initialize(dir = nil, worker:, prefix: nil, dynamic_imports: :inline, aliases: {}, platform: 'neutral')
      super(dir)
      @worker = worker
      @prefix = prefix
      @dynamic_imports = dynamic_imports
      @aliases = aliases
      @platform = platform
    end

    def call(environment, input)
      @environment = environment
      @input = input
      @accept = input[:content_types].last
      @entry = input[:source_file]
      @digests = {}

      config = {
        entry: @entry,
        entryDigest: digest_for(@entry),
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
        @worker.build(config, logger: @environment.logger) { |method, args| answer(method, *args) }
      rescue WorkerDied => e
        retry if (attempts += 1) == 1 && !@worker.stopping?
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
        id = @environment.find(importee, importer, accept: @accept)&.source_file
        { id: id, digest: digest_for(id) } if id
      when 'load'
        id = args.first
        if id == @entry
          { code: utf8(@input[:source]), digest: digest_for(@entry) }
        elsif (asset = @environment.find(id, accept: @accept))
          { code: utf8(asset.source), digest: asset.hexdigest }
        end
      when 'glob'
        glob, importer = args
        glob_module(glob, importer: importer)
      when 'resolveDynamicImport'
        resolve_dynamic_import(*args)
      end
    end

    # The digest of what `load` returns for +id+: the export input for the
    # entry, otherwise the processed asset's.
    def digest_for(id)
      @digests[id] ||= if id == @entry
        @environment.digestor.hexdigest(@input[:source])
      else
        @environment.find(id, accept: @accept)&.hexdigest
      end
    end

    def utf8(string)
      string.encoding == Encoding::BINARY ? string.dup.force_encoding(Encoding::UTF_8) : string
    end

    # "./" and "../" globs are relative to +importer+, like export_dependencies.
    def glob_module(glob, importer:)
      code = String.new
      exports = []
      digests = {}
      @environment.resolve(glob, importer, accept: @accept, npm: true).each_with_index do |f, i|
        digests[f.source_file] = digest_for(f.source_file)
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
      { code: code, digests: digests }
    end

    def resolve_dynamic_import(importee, importer)
      asset = @environment.find(importee, importer, accept: @accept, npm: true)
      asset ||= @environment.find(importee.delete_suffix('.js') + "/index.js", importer, accept: @accept, npm: true)
      asset ||= @environment.find(importee.gsub(/\/[^\/]+$/, '') + "/dist/index.js", importer, accept: @accept, npm: true)
      return if asset.nil?

      if asset.source_file == @input[:source_file]
        { id: @entry, digest: digest_for(@entry) }
      elsif @dynamic_imports == :keep
        { external: true, path: File.join("/", *[@prefix, asset.path].compact) }
      else
        { id: asset.source_file, digest: digest_for(asset.source_file) }
      end
    end
  end
end
