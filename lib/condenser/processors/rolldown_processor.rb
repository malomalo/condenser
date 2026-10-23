# frozen_string_literal: true

require 'json'

class Condenser::RolldownProcessor

  SCRIPT = File.expand_path('rolldown_processor.js', __dir__)
  DYNAMIC_IMPORTS = %i[inline keep].freeze

  @@setup = []

  def self.install_npm_packages(npm_path)
    return if @@setup.include?(npm_path)

    ::Condenser::NodeProcessor.new(npm_path).npm_install('rolldown')
    @@setup << npm_path
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

  def initialize(dir = nil, prefix: nil, dynamic_imports: :inline, bundler_path: nil, aliases: {}, platform: 'neutral', max_memory: Condenser::NodeWorker::MAX_MEMORY)
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
      @worker ||= Condenser::NodeWorker.new(
        Condenser::NodeProcessor.new(@npm_dir).binary,
        rolldown_path,
        script: SCRIPT,
        name: 'rolldown',
        max_memory: @max_memory,
        max_old_space_size: 5120
      )
    end
  end

  def rolldown_path
    @bundler_path || (@npm_dir ? File.join(@npm_dir, 'node_modules', 'rolldown') : 'rolldown')
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
      rescue Condenser::NodeWorker::WorkerDied => e
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
        glob_module(args.first)
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

    def glob_module(glob)
      code = String.new
      exports = []
      digests = {}
      @environment.resolve(glob, nil, accept: @accept, npm: true).each_with_index do |f, i|
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
