require 'set'
require 'digest/md5'
require 'digest/sha1'
require 'digest/sha2'
require 'condenser/export'

class Condenser
  class Asset
    
    include EncodingUtils
    
    attr_reader :environment, :filename, :content_types, :source_file, :source_path
    attr_reader :linked_assets, :dependencies
    attr_writer :source, :sourcemap

    attr_accessor :imports
    
    def initialize(env, attributes={})
      @environment    = env
      
      @filename       = attributes[:filename]
      @content_types  = Array(attributes[:content_types] || attributes[:content_type])

      @source_file    = attributes[:source_file]
      @source_path    = attributes[:source_path]
      
      @linked_assets  = Set.new
      @dependencies   = Set.new
      
      @processed      = false
      @exported       = false
    end
    
    def path
      filename.sub(/\.(\w+)$/) { |ext| "-#{etag}#{ext}" }
    end
    
    def content_type
      @content_types.last
    end
    
    def process
      process! if @processed == false
    end
    
    def basepath
      dirname, basename, extensions, mime_types = @environment.decompose_path(filename)
      [dirname, basename].compact.join('/')
    end
    
    def cache_key(data)
    end
    
    def process!(source=nil, source_digest=nil, content_digest=nil)
      source ||= File.binread(@source_file)
      source_digest ||= Digest::SHA1.base64digest(source)
      content_digest ||= Digest::SHA1.base64digest(@content_types.join(':'))

      result = @environment.cache.fetch("process/#{source_digest}/#{content_digest}") do
        dirname, basename, extensions, mime_types = @environment.decompose_path(@source_file)
        data = {
          source: source,
          source_file: @source_file,
          source_digest: source_digest,
        
          filename: @filename.dup,
          content_type: mime_types,

          map: nil,
          linked_assets: [],
          dependencies: []
        }
        
        while @environment.templates.has_key?(data[:content_type].last)
          templator = @environment.templates[data[:content_type].pop]
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
            processor.call(@environment, data)
          end
        end
      
        if data[:content_type].last != @content_types.last && @environment.transformers.has_key?(data[:content_type].last)
          @environment.transformers[data[:content_type].pop].each do |to_mime_type, processor|
            processor.call(@environment, data)
            data[:content_type] << to_mime_type
          end
        end
      
        if mime_types != @content_types
          raise ContentTypeMismatch, "mime type(s) \"#{@content_types.join(', ')}\" does not match requested mime type(s) \"#{data[:mime_types].join(', ')}\""
        end
      
        data[:digest] = @environment.digestor.digest(data[:source])
        data[:digest_name] = @environment.digestor.name.sub(/^.*::/, '').downcase
        data
      end
      @processed = true

      @source = result[:source]
      @sourcemap = result[:map]
      @filename = result[:filename]
      @content_types = result[:content_type]
      @linked_assets = result[:linked_assets]
      @digest = result[:digest]
      @digest_name = result[:digest_name]
      @dependencies = result[:dependencies]
    end
    
    def export
      source ||= File.binread(@source_file)
      source_digest ||= Digest::SHA1.base64digest(source)
      content_digest ||= Digest::SHA1.base64digest(@content_types.join(':'))
      
      process!(source, source_digest, content_digest) if !@processed
      
      result = @environment.cache.fetch("export/#{source_digest}/#{content_digest}") do
        dirname, basename, extensions, mime_types = @environment.decompose_path(@filename)
        data = {
          source: @source,
          source_file: @source_file,
          source_digest: source_digest,
        
          filename: @filename.dup,
          content_types: @content_types,

          sourcemap: nil,
          linked_assets: [],
          dependencies: []
        }
        @environment.exporters[content_type]&.call(@environment, data)
        @environment.minifiers[content_type]&.call(@environment, data)
        data[:digest] = @environment.digestor.digest(data[:source])
        data[:digest_name] = @environment.digestor.name.sub(/^.*::/, '').downcase
        data
      end
      
      Export.new(@environment, result)
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
      "#{@digest_name}-#{[@digest].pack('m0')}"
    end
    
    def to_json
      { path: path, digest: hexdigest, size: size, integrity: integrity }
    end
    
    def write(output_directory)
      files = @environment.writers_for_mime_type(content_type).map do |writer|
        writer[0].call(output_directory, self)
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