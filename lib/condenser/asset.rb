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
    
    def stat
      @stat ||= File.stat(@source_file)
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
        @process_dependencies
      end
    
      d = []
      deps.each do |i|
        i = [i, @content_types] if i.is_a?(String)
        @environment.resolve(i[0], File.dirname(@source_file), accept: i[1]).each do |asset|
          d << asset
        end
      end
      d
    end
    
    def export_dependencies
      deps = @environment.cache.fetch "export-deps/#{cache_key}" do
        process
        @export_dependencies + @process_dependencies
      end
      
      d = []
      deps.each do |i|
        i = [i, @content_types] if i.is_a?(String)
        @environment.resolve(i[0], File.dirname(@source_file), accept: i[1]).each do |asset|
          d << asset
        end
      end
      d
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
    
    def all_process_dependencies
      f = [@source_file]
      all_dependenies(process_dependencies, [], :process_dependencies) do |dep|
        f << dep.source_file
      end
      f
    end
    
    def all_export_dependencies
      f = [@source_file]
      all_dependenies(export_dependencies, [], :export_dependencies) do |dep|
        f << dep.source_file
      end
      f
    end
    
    def cache_key
      Digest::SHA1.base64digest(JSON.generate([
        Condenser::VERSION,
        @source_file,
        stat.ino,
        stat.mtime.to_f,
        stat.size,
        @content_types_digest
      ]))
    end
    
    def process_cache_version
      return @pcv if @pcv

      f = []
      all_dependenies(process_dependencies, [], :process_dependencies) do |dep|
        f << [dep.source_file, dep.stat.ino, dep.stat.mtime.to_f, dep.stat.size]
      end

      @pcv = Digest::SHA1.base64digest(JSON.generate(f))
    end
    
    def export_cache_version
      return @ecv if @ecv

      f = []
      all_dependenies(export_dependencies, [], :export_dependencies) do |dep|
        f << [dep.source_file, dep.stat.ino, dep.stat.mtime.to_f, dep.stat.size]
      end

      @ecv = Digest::SHA1.base64digest(JSON.generate(f))
    end
    
    def needs_reprocessing!
      @processed = false
      @pcv = nil
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
            linked_assets: [],
            process_dependencies: [],
            export_dependencies: [],
            
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
      
          if mime_types != @content_types
            raise ContentTypeMismatch, "mime type(s) \"#{@content_types.join(', ')}\" does not match requested mime type(s) \"#{data[:mime_types].join(', ')}\""
          end
      
          data[:digest] = @environment.digestor.digest(data[:source])
          data[:digest_name] = @environment.digestor.name.sub(/^.*::/, '').downcase

          # Do this here and at the end so cache_key can be calculated if we
          # run this block
          @source = data[:source]
          @sourcemap = data[:map]
          @filename = data[:filename]
          @content_types = data[:content_type]
          @digest = data[:digest]
          @digest_name = data[:digest_name]
          @linked_assets = data[:linked_assets]
          @process_dependencies = data[:process_dependencies]
          @export_dependencies = data[:export_dependencies]
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
      @linked_assets = result[:linked_assets]
      @process_dependencies = result[:process_dependencies]
      @export_dependencies  = result[:export_dependencies]
      @default_export = result[:default_export]
      @exports = result[:exports]
      @processors = result[:processors]
      load_processors

      @processed = true
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
        
          if exporter = @environment.exporters[content_type]
            exporter.call(@environment, data)
          end

          if minifier = @environment.minifier_for(content_type)
            minifier.call(@environment, data)
          end
        
          data[:digest] = @environment.digestor.digest(data[:source])
          data[:digest_name] = @environment.digestor.name.sub(/^.*::/, '').downcase
          data
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