require 'set'
require 'digest/md5'
require 'digest/sha1'
require 'digest/sha2'

class Condenser
  class Asset
    
    include EncodingUtils
    
    attr_reader :environment, :filename, :content_types, :source_file
    attr_reader :linked_assets, :dependencies
    
    attr_accessor :source, :sourcemap, :exports, :imports
    
    def initialize(env, attributes={})
      @environment    = env
      @filename       = attributes[:filename]
      @content_types  = Array(attributes[:content_types] || attributes[:content_type])
      
      @source_file    = attributes[:source_file]
      
      @linked_assets  = Set.new

      @dependencies   = Set.new
      @exports        = false
      
      @processed      = false
      @exported       = false
    end
    
    def new_context_class
      @environment.context_class.new(self)
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
    
    def process!
      @source = File.binread(@source_file)
      dirname, basename, extensions, mime_types = @environment.decompose_path(source_file)
      
      while @environment.templates.has_key?(mime_types.last)
        templator = @environment.templates[mime_types.pop]
        templator.call(self)
        @filename = @filename.gsub(/\.#{extensions.last}$/, '')
      end
      
      case @environment.mime_types[mime_types.last][:charset]
      when :unicode
        detect_unicode(@source)
      when :css
        detect_css(@source)
      when :html
        detect_html(@source)
      else
        detect(@source) if mime_types.last.start_with?('text/')
      end
      
      if @environment.preprocessors.has_key?(content_type)
        @environment.preprocessors[content_type].each do |processor|
          processor.call(self)
        end
      end
      
      if @environment.transformers.has_key?(mime_types.last)
        @environment.transformers[mime_types.pop].each do |to_mime_type, processor|
          processor.call(self)
          mime_types << to_mime_type
        end
      end
      
      if mime_types != @content_types
        raise ContentTypeMismatch, "mime type(s) \"#{@content_types.join(', ')}\" does not match requested mime type(s) \"#{mime_types.join(', ')}\""
      end
      
      @digest = @environment.digestor.digest(@source)
      @digest_name = @environment.digestor.name.sub(/^.*::/, '').downcase
      @processed = true
    end
    
    def export
      export! if @exported == false
    end
    
    def export!
      process
      
      @environment.exporters[content_type]&.call(self)
      
      @exported = true
    end
    
    def to_s
      process
      @source
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
      
    # Public: Compare assets.
    #
    # Assets are equal if they share the same path and digest.
    #
    # Returns true or false.
    # def eql?(other)
    #   self.class == other.class && self.filename == other.filename && self.content_types == other.content_types
    # end
    # alias_method :==, :eql?
    
  end
end