# frozen_string_literal: true

require 'json'

class Condenser::RolldownProcessor < Condenser::Processor

  SCRIPT = File.expand_path('rolldown_processor.js', __dir__)
  DYNAMIC_IMPORTS = %i[inline keep].freeze
  # Rolldown's module types, less the ones that emit a file (asset, copy,
  # css), since only the JavaScript bundle is kept.
  MODULE_TYPES = %w[base64 binary dataurl empty js json jsx text ts tsx].freeze
  SOURCEMAPS = [false, :linked, :hidden].freeze

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

  def options
    options = {prefix: @prefix, dynamic_imports: @dynamic_imports, aliases: @aliases, minify: @minify, rolldown: @rolldown_version}
    options[:platform] = @platform if @platform != 'neutral'
    options[:module_types] = @module_types if !@module_types.empty?
    options[:sourcemap] = @sourcemap if @sourcemap
    options
  end

  def initialize(dir = nil, prefix: nil, dynamic_imports: :inline, bundler_path: nil, aliases: {}, platform: 'neutral', minify: false, module_types: {}, sourcemap: false, max_memory: Condenser::NodeWorker::MAX_MEMORY)
    unless DYNAMIC_IMPORTS.include?(dynamic_imports)
      raise ArgumentError, "dynamic_imports must be :inline or :keep, got #{dynamic_imports.inspect}"
    end
    unless minify == true || minify == false
      raise ArgumentError, "minify must be true or false, got #{minify.inspect}"
    end
    unless SOURCEMAPS.include?(sourcemap)
      raise ArgumentError, "sourcemap must be false, :linked or :hidden, got #{sourcemap.inspect}"
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
    @minify = minify
    @module_types = normalize_module_types(module_types)
    @sourcemap = sourcemap
    @max_memory = max_memory
    @lock = Mutex.new
    @rolldown_version = self.class.read_version(rolldown_path) if bundler_path || dir
  end

  def call(environment, input)
    Runner.new(@npm_dir, worker: worker, prefix: @prefix, dynamic_imports: @dynamic_imports, aliases: @aliases, platform: @platform, minify: @minify, module_types: @module_types, sourcemap: @sourcemap).call(environment, input)
  end

  # { png: :dataurl } as { "png" => "dataurl" }, sorted by extension.
  def normalize_module_types(module_types)
    unless module_types.is_a?(Hash)
      raise ArgumentError, "module_types must be a Hash of extension => module type, got #{module_types.inspect}"
    end

    module_types.to_h do |ext, type|
      unless (ext.is_a?(Symbol) || ext.is_a?(String)) && ext.to_s.match?(/\A[A-Za-z0-9_-]+\z/)
        hint = " (without the leading dot: #{ext.to_s.delete_prefix('.').to_sym.inspect})" if ext.to_s.start_with?('.')
        raise ArgumentError, "module_types keys must be file extensions like :png, got #{ext.inspect}#{hint}"
      end
      unless (type.is_a?(Symbol) || type.is_a?(String)) && MODULE_TYPES.include?(type.to_s)
        raise ArgumentError, "module_types[#{ext.inspect}] must be one of #{MODULE_TYPES.map(&:to_sym).inspect}, got #{type.inspect}"
      end
      [ext.to_s, type.to_s]
    end.sort.to_h
  end
  private :normalize_module_types

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
    JSON_TYPE = 'application/json'

    def initialize(dir = nil, worker:, prefix: nil, dynamic_imports: :inline, aliases: {}, platform: 'neutral', minify: false, module_types: {}, sourcemap: false)
      super(dir)
      @worker = worker
      @prefix = prefix
      @dynamic_imports = dynamic_imports
      @aliases = aliases
      @platform = platform
      @minify = minify
      @module_types = module_types
      @sourcemap = sourcemap
    end

    def call(environment, input)
      @environment = environment
      @input = input
      @accept = input[:content_types].last
      @entry = input[:source_file]
      @digests = {}
      @json = Set.new

      config = {
        entry: @entry,
        entryDigest: digest_for(@entry),
        cwd: environment.base || Dir.pwd,
        # "node_modules" is looked up from the importer up, like Node, so a
        # package's nested node_modules come before the npm path's.
        modules: npm_path ? ['node_modules', npm_module_path] : [],
        aliases: @aliases,
        platform: @platform,
        minify: @minify,
        moduleTypes: @module_types.to_h { |ext, type| [".#{ext}", type] }
      }
      if @sourcemap
        config[:sourcemap] = true
        config[:sourceRoots] = [config[:cwd], *environment.path, npm_path].compact.uniq
      end

      result = exec_runtime(config)
      if @sourcemap
        # Asset#export adds the sourceMappingURL comment for :linked.
        input[:source] = result['code']
        input[:sourcemap] = result['map']
        input[:sourcemap_linked] = @sourcemap == :linked
      else
        input[:source] = result
      end
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
        return module_file(importee, importer) if module_type?(importee)

        # npm: false; Rolldown resolves node_modules when this is nil.
        id = @environment.find(importee, importer, accept: @accept)&.source_file
        # JSON needs its extension, as in Node and Rolldown.
        if id.nil? && importee.end_with?('.json')
          id = @environment.find(importee, importer, accept: JSON_TYPE)&.source_file
          @json << id if id
        end
        { id: id, type: @json.include?(id) ? 'json' : 'js', digest: digest_for(id) } if id
      when 'load'
        id = args.first
        if id == @entry
          { code: utf8(@input[:source]), digest: digest_for(@entry) }
        elsif (asset = asset_for(id))
          { code: utf8(asset.source), digest: asset.hexdigest }
        end
      when 'glob'
        glob, importer = args
        glob_module(glob, importer: importer)
      when 'resolveDynamicImport'
        resolve_dynamic_import(*args)
      end
    end

    def module_type?(importee)
      @module_types.key?(File.extname(importee).delete_prefix('.'))
    end

    # A file imported with a module type is loaded by Rolldown itself, so
    # Ruby only finds it: an absolute path, "./" or "../" relative to
    # +importer+, in the load paths, or through an alias. If it's not found
    # Rolldown tries node_modules, then fails with "Could not resolve".
    def module_file(importee, importer)
      path = existing_file(importee, importer) || aliased_file(importee, importer)
      { id: path } if path
    end

    # Like Rolldown, an alias matches the whole name or a "name/" prefix.
    def aliased_file(importee, importer)
      @aliases.each do |name, targets|
        name = name.to_s
        next if importee != name && !importee.start_with?("#{name}/")
        Array(targets).each do |target|
          path = existing_file(target + importee.delete_prefix(name), importer) if target.is_a?(String)
          return path if path
        end
      end
      nil
    end

    def existing_file(name, importer)
      @environment.expand_dependency_path(name, source_file: importer)
    rescue Condenser::FileNotFound
      nil
    end

    # The digest of what `load` returns for +id+: the export input for the
    # entry, otherwise the processed asset's.
    def digest_for(id)
      @digests[id] ||= if id == @entry
        @environment.digestor.hexdigest(@input[:source])
      else
        asset_for(id)&.hexdigest
      end
    end

    # The asset built from the file +id+, or nil if +id+ isn't a file
    # Condenser can turn into JavaScript (or JSON), so Rolldown loads it
    # itself rather than getting another file with the same name.
    def asset_for(id)
      asset = @environment.find(id, accept: accept_for(id))
      asset if asset&.source_file == id
    end

    def accept_for(id)
      @json.include?(id) ? JSON_TYPE : @accept
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
      # A file with a module type is bundled even with dynamic_imports: :keep,
      # since it isn't a JavaScript file that can be imported on its own.
      return module_file(importee, importer) if module_type?(importee)

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
