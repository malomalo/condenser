# frozen_string_literal: true

require 'set'
require 'digest/md5'
require 'digest/sha1'
require 'digest/sha2'
require 'condenser/export'

class Condenser
  class Asset
    
    include EncodingUtils
    
    attr_reader :environment, :filename, :content_types, :source_file, :source_path
    attr_reader :linked_assets, :content_types_digest, :exports
    attr_writer :source, :sourcemap

    attr_accessor :imports, :processed
    
    def initialize(env, attributes={})
      @environment    = env
      
      @filename       = attributes[:filename]
      @content_types  = Array(attributes[:content_types] || attributes[:content_type])
      @content_types_digest = Digest::SHA1.base64digest(@content_types.join(':'))

      @source_file    = attributes[:source_file]
      @source_path    = attributes[:source_path]
      
      @linked_assets        = Set.new
      @process_dependencies = Set.new
      @export_dependencies  = Set.new
      @default_export       = nil
      @exports              = nil
      @processed            = false
      @pcv                  = nil
      @export               = nil
      @ecv                  = nil
      @processors_loaded    = false
      @processors           = Set.new
    end
    
    def path
      filename.sub(/\.(\w+)$/) { |ext| "-#{etag}#{ext}" }
    end
    
    def content_type
      @content_types.last
    end
    
    def basepath
      dirname, basename, extensions, mime_types = @environment.decompose_path(filename)
      [dirname, basename].compact.join('/')
    end
    
    def restat!
      @stat = nil
    end
    
    def inspect
      dirname, basename, extensions, mime_types = @environment.decompose_path(@filename)
      <<-TEXT
        #<#{self.class.name}##{self.object_id} @filename=#{@filename} @content_types=#{@content_types.inspect} @source_file=#{@source_file} @source_mime_types=#{mime_types.inspect}>
      TEXT
    end
    
    def process_dependencies
      deps = @environment.cache.fetch "direct-deps/#{cache_key}" do
        process
        @process_dependencies.map { |fn| [normalize_filename_base(fn[0]), fn[1]] }
      end
    
      deps.inject([]) do |memo, i|
        i[0] = File.join(@environment.base, i[0].delete_prefix('!')) if i[0].start_with?('!') && @environment.base
        @environment.resolve(i[0], File.dirname(@source_file), accept: i[1]).each do |asset|
          memo << asset
        end
        memo
      end
    end
    
    def export_dependencies
      deps = @environment.cache.fetch "export-deps/#{cache_key}" do
        process
        (@export_dependencies + @process_dependencies).map { |fn| [normalize_filename_base(fn[0]), fn[1]] }
      end
      
      deps.inject([]) do |memo, i|
        i[0] = File.join(@environment.base, i[0].delete_prefix('!')) if i[0].start_with?('!') && @environment.base
        @environment.resolve(i[0], File.dirname(@source_file), accept: i[1]).each do |asset|
          memo << asset
        end
        memo
      end
    end
    
    def has_default_export?
      process
      @default_export
    end
    
    def has_exports?
      process
      @exports
    end

    def load_processors
      return if @processors_loaded

      @processors_loaded = true
      process
      @processors.map! { |p| p.is_a?(String) ? p.constantize : p }
      @environment.load_processors(*@processors)
    end
    
    def all_dependenies(deps, visited, meth, &block)
      deps.each do |dep|
        if !visited.include?(dep.source_file)
          visited << dep.source_file
          block.call(dep)
          all_dependenies(dep.send(meth), visited, meth, &block)
        end
      end
    end
    
    def all_process_dependencies(visited = Set.new)
      f = []
      if !visited.include?(@source_file)
        f << @source_file
        visited << self.source_file
      end
      
      all_dependenies(process_dependencies, visited, :process_dependencies) do |dep|
        f << dep.source_file
      end
      f
    end
    
    def all_export_dependencies(visited = Set.new)
      f = []
      if !visited.include?(@source_file)
        f << @source_file
        visited << self.source_file
      end
      
      all_dependenies(export_dependencies, visited, :export_dependencies) do |dep|
        f << dep.source_file
      end
      f
    end
    
    def cache_key
      @cache_key ||= Digest::SHA1.base64digest(JSON.generate([
        Condenser::VERSION,
        @environment.pipline_digest,
        normalize_filename_base(@source_file),
        Digest::SHA256.file(@source_file).hexdigest,
        @content_types_digest
      ]))
    end
    
    # Remove Enviroment base if it exists. This allows two of the same repos
    # in a different location to use the same cache (like capistrano deploys)
    def normalize_filename_base(source_filename)
      if @environment.base && source_filename.start_with?(@environment.base)
        '!'+source_filename.delete_prefix(@environment.base).delete_prefix(File::SEPARATOR)
      else
        source_filename
      end
    end
    
    def process_cache_version
      return @pcv if @pcv

      f = []
      all_dependenies(process_dependencies, Set.new, :process_dependencies) do |dep|
        f << [
          normalize_filename_base(dep.source_file),
          Digest::SHA256.file(dep.source_file).hexdigest
        ]
      end
      
      @pcv = Digest::SHA1.base64digest(JSON.generate(f))
    end
    
    def export_cache_version
      return @ecv if @ecv

      f = []
      all_dependenies(export_dependencies, Set.new, :export_dependencies) do |dep|
        f << [
          normalize_filename_base(dep.source_file),
          Digest::SHA256.file(dep.source_file).hexdigest
        ]
      end

      @ecv = Digest::SHA1.base64digest(JSON.generate(f))
    end
    
    def needs_reprocessing!
      @processed = false
      @pcv = nil
      @cache_key = nil
      needs_reexporting!
    end
    
    def needs_reexporting!
      restat!
      @export = nil
      @ecv = nil
    end
    
    def process
      return if @processed
      
      result = @environment.build do
        @environment.cache.fetch_if(Proc.new {"process/#{cache_key}/#{process_cache_version}"}, "direct-deps/#{cache_key}") do
          @source = File.binread(@source_file)
          dirname, basename, extensions, mime_types = @environment.decompose_path(@source_file)
          
          data = {
            source: @source,
            source_file: @source_file,
        
            filename: @filename.dup,
            content_type: mime_types,

            map: nil,
            linked_assets: Set.new,
            process_dependencies: Set.new,
            export_dependencies: Set.new,
            
            processors: Set.new
          }
        
          while @environment.templates.has_key?(data[:content_type].last)
            templator = @environment.templates[data[:content_type].pop]
            
            templator_klass = (templator.is_a?(Class) ? templator : templator.class)
            data[:processors] << templator_klass.name
            @environment.load_processors(templator_klass)
            
            templator.call(@environment, data)
            data[:filename] = data[:filename].gsub(/\.#{extensions.last}$/, '')
          end
          
          case @environment.mime_types[data[:content_type].last][:charset]
          when :unicode
            detect_unicode(data[:source])
          when :css
            detect_css(data[:source])
          when :html
            detect_html(data[:source])
          else
            detect(data[:source]) if mime_types.last.start_with?('text/')
          end
          
          if @environment.preprocessors.has_key?(data[:content_type].last)
            @environment.preprocessors[data[:content_type].last].each do |processor|
              processor_klass = (processor.is_a?(Class) ? processor : processor.class)
              data[:processors] << processor_klass.name
              @environment.load_processors(processor_klass)

              @environment.logger.info { "Pre Processing #{self.filename} with #{processor.name}" }
              processor.call(@environment, data)
            end
          end
      
          if data[:content_type].last != @content_types.last && @environment.transformers.has_key?(data[:content_type].last)
            from_mime_type = data[:content_type].pop
            @environment.transformers[from_mime_type].each do |to_mime_type, processor|
              processor_klass = (processor.is_a?(Class) ? processor : processor.class)
              data[:processors] << processor_klass.name
              @environment.load_processors(processor_klass)
              
              @environment.logger.info { "Transforming #{self.filename} from #{from_mime_type} to #{to_mime_type} with #{processor.name}" }
              processor.call(@environment, data)
              data[:content_type] << to_mime_type
            end
          end
          
          if @environment.postprocessors.has_key?(data[:content_type].last)
            @environment.postprocessors[data[:content_type].last].each do |processor|
              processor_klass = (processor.is_a?(Class) ? processor : processor.class)
              data[:processors] << processor_klass.name
              @environment.load_processors(processor_klass)

              @environment.logger.info { "Post Processing #{self.filename} with #{processor.name}" }
              processor.call(@environment, data)
            end
          end
      
          if mime_types != @content_types
            raise ContentTypeMismatch, "mime type(s) \"#{@content_types.join(', ')}\" does not match requested mime type(s) \"#{data[:mime_types].join(', ')}\""
          end
      
          data[:digest] = @environment.digestor.digest(data[:source])
          data[:digest_name] = @environment.digestor.name.sub(/^.*::/, '').downcase
          data[:process_dependencies] = normialize_dependency_names(data[:process_dependencies])
          data[:export_dependencies] = normialize_dependency_names(data[:export_dependencies])

          # Do this here and at the end so cache_key can be calculated if we
          # run this block
          @source = data[:source]
          @sourcemap = data[:map]
          @filename = data[:filename]
          @content_types = data[:content_type]
          @digest = data[:digest]
          @digest_name = data[:digest_name]
          @linked_assets = Set.new(data[:linked_assets])
          @process_dependencies = Set.new(data[:process_dependencies])
          @export_dependencies = Set.new(data[:export_dependencies])
          @default_export = data[:default_export]
          @exports = data[:exports]
          @processors = data[:processors]
          @processors_loaded = true
          @processed = true
          data
        end
      end
      
      @source = result[:source]
      @sourcemap = result[:map]
      @filename = result[:filename]
      @content_types = result[:content_type]
      @digest = result[:digest]
      @digest_name = result[:digest_name]
      @linked_assets = Set.new(result[:linked_assets])
      @process_dependencies = Set.new(result[:process_dependencies])
      @export_dependencies  = Set.new(result[:export_dependencies])
      @default_export = result[:default_export]
      @exports = result[:exports]
      @processors = result[:processors]
      load_processors

      @processed = true
    end
    
    def normialize_dependency_names(deps)
      deps.map do |fn|
        if fn.is_a?(String)
          dirname, basename, extensions, mime_types = @environment.decompose_path(fn, source_file)
          [dirname ? File.join(dirname, basename) : basename, mime_types.empty? ? @content_types : mime_types]
        else
          fn
        end
      end
    end
    
    def export
      return @export if @export
      
      @export = @environment.build do
        data = @environment.cache.fetch_if(Proc.new {"export/#{cache_key}/#{export_cache_version}"}, "export-deps/#{cache_key}") do
          process
          dirname, basename, extensions, mime_types = @environment.decompose_path(@filename)
          data = {
            source: @source.dup,
            source_file: @source_file,
        
            filename: @filename.dup,
            content_types: @content_types,

            sourcemap: nil,
            linked_assets: [],
            process_dependencies: [],
            export_dependencies: []
          }
        
          if @environment.exporters.has_key?(content_type)
            @environment.exporters[content_type].each do |exporter|
              @environment.logger.info { "Exporting #{self.filename} with #{exporter.name}" }
              exporter.call(@environment, data)
            end
          end

          if minifier = @environment.minifier_for(content_type)
            @environment.logger.info { "Minifing #{self.filename} with #{minifier.name}" }
            minifier.call(@environment, data)
          end
        
          data[:digest] = @environment.digestor.digest(data[:source])
          data[:digest_name] = @environment.digestor.name.sub(/^.*::/, '').downcase
          data
        end

        if @environment.build_cache.listening
          # TODO we could skip file and all their depencies here if they are
          # already in build_cache.@export_dependencies
          all_export_dependencies.each do |sf|
            @environment.build_cache.instance_variable_get(:@export_dependencies)[sf]&.add(self)
          end
        end

        Export.new(@environment, data)
      end
    end
    
    def to_s
      process
      @source
    end
    
    def source
      process
      @source
    end
    
    def sourcemap
      process
      @sourcemap
    end
    
    def length
      process
      @source.bytesize
    end
    alias size length
    
    def digest
      process
      @digest
    end
    
    def charset
      @source.encoding.name.downcase
    end

    # Public: Returns String hexdigest of source.
    def hexdigest
      process
      @digest.unpack('H*'.freeze).first
    end
    alias_method :etag, :hexdigest
    
    def integrity
      process
      "#{@digest_name}-#{[@digest].pack('m0')}"
    end
    
    def to_json
      { path: path, digest: hexdigest, size: size, integrity: integrity }
    end
    
    def write(output_directory)
      files = @environment.writers_for_mime_type(content_type).map do |writer|
        writer.call(output_directory, self)
      end
      files.flatten.compact
    end
    
    def ext
      File.extname(filename)
    end
      
    # Public: Compare assets.
    #
    # Assets are equal if they share the same path and digest.
    #
    # Returns true or false.
    def eql?(other)
      self.class == other.class && self.filename == other.filename && self.content_types == other.content_types
    end
    alias_method :==, :eql?
    
  end
end