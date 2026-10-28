# frozen_string_literal: true

class Condenser
  class Export

    attr_reader :filename, :source, :sourcemap, :content_types, :digest, :digest_name, :etag, :type

    def initialize(env, input={})
      @environment = env
      
      @source = input[:source]
      @sourcemap = input[:sourcemap]
      @filename = input[:filename]
      @content_types = input[:content_types]
      @digest = input[:digest]
      @digest_name = input[:digest_name]
      @etag = input[:etag]
      @type = input[:type]
    end
    
    def path
      filename.sub(/\.(\w+)$/) { |ext| "-#{etag}#{ext}" }
    end
    
    def content_type
      @content_types.last
    end

    # The source map is written and served at the export's path plus ".map".
    def sourcemap_path
      "#{path}.map" if @sourcemap
    end
    
    def to_s
      @source
    end

    # Without the environment and the source.
    def inspect
      "#<#{self.class.name} filename=#{filename.inspect} content_types=#{content_types.inspect} etag=#{etag.inspect}>"
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
    
    def integrity
      "#{@digest_name}-#{[@digest].pack('m0')}"
    end
    
    def to_json
      {
        path: path,
        etag: etag,
        type: type,
        size: size,
        digest: hexdigest,
        integrity: integrity,
        sourcemap: @sourcemap ? sourcemap_path : nil
      }
    end
    
    def write(output_directory)
      files = write_asset(output_directory, self)
      files += write_asset(output_directory, sourcemap_export) if @sourcemap
      files
    end

    def sourcemap_export
      Condenser::Sourcemap.new(path: sourcemap_path, filename: "#{filename}.map", source: @sourcemap, content_types: ['application/json'])
    end
    
    def ext
      File.extname(filename)
    end

    private

    def write_asset(output_directory, asset)
      files = @environment.writers_for_mime_type(asset.content_types.last).map do |writer|
        if writer.exist?(asset)
          @environment.logger.debug "Skipping #{ asset.path }, already exists"
        else
          @environment.logger.info "Writing #{ asset.path }"
          writer.call(output_directory, asset)
        end
      end
      files.flatten.compact
    end
    
  end
end