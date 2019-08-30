class Condenser
  class Export

    attr_reader :filename, :source, :sourcemap, :content_types, :digest, :digest_name

    def initialize(env, input={})
      @environment = env
      
      @source = input[:source]
      @sourcemap = input[:map]
      @filename = input[:filename]
      @content_types = input[:content_types]
      @digest = input[:digest]
      @digest_name = input[:digest_name]
    end
    
    def path
      filename.sub(/\.(\w+)$/) { |ext| "-#{etag}#{ext}" }
    end
    
    def content_type
      @content_types.last
    end
    
    def to_s
      @source
    end
    
    def length
      @source.bytesize
    end
    alias size length
    
    def digest
      @digest
    end
    
    def charset
      @source.encoding.name.downcase
    end

    # Public: Returns String hexdigest of source.
    def hexdigest
      @digest.unpack('H*'.freeze).first
    end
    alias_method :etag, :hexdigest
    
    def integrity
      "#{@digest_name}-#{[@digest].pack('m0')}"
    end
    
    def to_json
      {
        'path' => path,
        'size' => size,
        'digest' => hexdigest,
        'integrity' => integrity
      }
    end
    
    def write(output_directory)
      files = @environment.writers_for_mime_type(content_type).map do |writer|
        if writer.exist?(self)
          @environment.logger.debug "Skipping #{ self.path }, already exists"
        else
          @environment.logger.info "Writing #{ self.path }"
          writer.call(output_directory, self)
        end
      end
      files.flatten.compact
    end
    
    def ext
      File.extname(filename)
    end
    
  end
end