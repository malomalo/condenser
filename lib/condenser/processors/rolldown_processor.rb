# frozen_string_literal: true

require 'json'
require 'securerandom'

# A drop-in alternative to Condenser::RollupProcessor that bundles with
# Rolldown. Ruby resolves and loads only what condenser knows about (the
# entry, load-path imports, processed sources such as .erb/.ejx/.jst/.svg,
# globs and dynamic imports); Rolldown resolves and reads node_modules itself.
# See rolldown_processor.js for the Node side.
class Condenser::RolldownProcessor

  SCRIPT = File.expand_path('rolldown_processor.js', __dir__)

  @@setup = []

  def self.setup(environment)
  end

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
    options = {prefix: @prefix, dynamic_imports: @dynamic_imports, aliases: @aliases}
    options[:platform] = @platform if @platform != 'neutral'
    options
  end

  # @param prefix [String] prefixed to the URL of kept dynamic imports
  # @param dynamic_imports [Symbol, false] :inline (the default) inlines
  #   dynamic imports; anything else (:keep, :local, false) keeps them as
  #   imports of the separately exported asset's URL
  # @param bundler_path [String] the rolldown package directory to load;
  #   defaults to +dir+/node_modules/rolldown
  # @param aliases [Hash] passed to Rolldown's resolve.alias
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
    # Used as the entry's id if the asset has no source file.
    VIRTUAL_ENTRY = '/__condenser_rolldown__/entry.js'

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
      @token = "#{SecureRandom.hex(8)}:"
      # The entry's source is always the input being exported, not what
      # condenser would load for that file.
      @entry = input[:source_file] || VIRTUAL_ENTRY

      config = {
        token: @token,
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
      io = IO.popen([binary, '--max_old_space_size=5120', SCRIPT, JSON.generate(config)], 'r+')
      buffer = String.new
      output = nil
      error = nil

      begin
        while IO.select([io]) && (chunk = io.read_nonblock(65_536))
          buffer << chunk
          while (newline = buffer.index("\n"))
            line = buffer.slice!(0, newline + 1)
            if !line.start_with?(@token)
              $stdout.write(line) unless line.strip.empty?
              next
            end

            message = JSON.parse(line.delete_prefix(@token))
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
        end
      rescue Errno::EPIPE, EOFError
      rescue Exception
        Process.kill('TERM', io.pid) rescue nil
        raise
      ensure
        io.close
      end

      if error
        raise exec_runtime_error("#{error[0]}: #{error[1]}")
      elsif !$?.success? || output.nil?
        raise exec_runtime_error(buffer.empty? ? "rolldown exited with #{$?}" : buffer)
      end
      output
    end

    private

    def base_for(importer)
      importer == @entry ? @input[:source_file] : importer
    end

    def answer(method, *args)
      case method
      when 'resolve'
        importee, importer = args
        # npm: false; Rolldown resolves node_modules when this is nil.
        @environment.find(importee, base_for(importer), accept: @accept)&.source_file
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

    # A module importing every file matched by +glob+, whose default export
    # is an array of their exports.
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
      base = base_for(importer)
      asset = @environment.find(importee, base, accept: @accept, npm: true)
      asset ||= @environment.find(importee.delete_suffix('.js') + "/index.js", base, accept: @accept, npm: true)
      asset ||= @environment.find(importee.gsub(/\/[^\/]+$/, '') + "/dist/index.js", base, accept: @accept, npm: true)
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
