# frozen_string_literal: true

require 'json'
require 'socket'

class Condenser::RolldownProcessor

  SCRIPT = File.expand_path('rolldown_processor.js', __dir__)

  @@setup = []

  def self.install_npm_packages(npm_path)
    return if @@setup.include?(npm_path)

    ::Condenser::NodeProcessor.new(npm_path).npm_install('rolldown')
    @@setup << npm_path
  end

  def self.call(environment, input)
    new(environment.npm_path).call(environment, input)
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
      package = path && File.join(path, 'package.json')
      JSON.parse(File.read(package))['version'] if package && File.exist?(package)
    end
  end

  def initialize(dir = nil, prefix: nil, dynamic_imports: :inline, bundler_path: nil, aliases: {}, platform: 'neutral')
    self.class.install_npm_packages(dir) if bundler_path.nil? && dir
    @npm_dir = dir
    @prefix = prefix
    @dynamic_imports = dynamic_imports
    @bundler_path = bundler_path
    @aliases = aliases
    @platform = platform
  end

  def call(environment, input)
    Runner.new(@npm_dir, prefix: @prefix, dynamic_imports: @dynamic_imports, bundler_path: @bundler_path, aliases: @aliases, platform: @platform).call(environment, input)
  end

  class Runner < Condenser::NodeProcessor
    def initialize(dir = nil, prefix: nil, dynamic_imports: :inline, bundler_path: nil, aliases: {}, platform: 'neutral')
      super(dir)
      @prefix = prefix
      @dynamic_imports = dynamic_imports
      @aliases = aliases
      @platform = platform
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
      io, child_io = UNIXSocket.pair
      begin
        pid = Process.spawn(binary, '--max_old_space_size=5120', SCRIPT, JSON.generate(config), in: File::NULL, 3 => child_io)
      rescue Exception
        io.close
        raise
      ensure
        child_io.close
      end
      output = nil
      error = nil

      begin
        while (line = io.gets)
          message = JSON.parse(line)
          case message['method']
          when 'done'
            output = message['args'][0]
          when 'error'
            error = message['args']
          when 'warn'
            @environment.logger.warn(message['args'][0])
          else
            ret = answer(message['method'], *message['args'])
            io.write(JSON.generate({rid: message['rid'], return: ret}), "\n")
          end
        end
      rescue Errno::EPIPE, Errno::ECONNRESET
      rescue Exception
        Process.kill('TERM', pid) rescue nil
        raise
      ensure
        io.close
        _, status = Process.wait2(pid)
      end

      if error
        raise exec_runtime_error("#{error[0]}: #{error[1]}")
      elsif !status.success? || output.nil?
        raise exec_runtime_error("rolldown exited with #{status}")
      end
      output
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
      elsif @dynamic_imports != :inline
        { external: true, path: File.join("/", *[@prefix, asset.path].compact) }
      else
        { id: asset.source_file }
      end
    end
  end
end
