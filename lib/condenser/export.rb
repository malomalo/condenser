# frozen_string_literal: true

require 'fileutils'
require 'condenser/utils'

class Condenser
  class Export

    attr_reader :filename, :source, :sourcemap, :content_types, :digest, :digest_name, :etag, :type

    def initialize(env, input={})
      @environment = env
      
      @source = input[:source]
      @sourcemap = input[:map]
      @sourcemap_linked = !!input[:map_linked]
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

    # Whether the export links to its source map, with a sourceMappingURL
    # comment and a SourceMap header.
    def sourcemap_linked?
      !!@sourcemap && @sourcemap_linked
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
        integrity: integrity
      }.tap { |json| json[:map] = sourcemap_path if @sourcemap }
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
      files << write_sourcemap(output_directory) if @sourcemap
      files.flatten.compact
    end

    # Uncompressed: maps are only fetched by devtools and error trackers.
    def write_sourcemap(output_directory)
      filename = File.join(output_directory, sourcemap_path)
      if ::File.exist?(filename)
        @environment.logger.debug "Skipping #{ sourcemap_path }, already exists"
      else
        @environment.logger.info "Writing #{ sourcemap_path }"
        FileUtils.mkdir_p(File.dirname(filename))
        Utils.atomic_write(filename) { |file| file.write(@sourcemap) }
      end
      "#{self.filename}.map"
    end
    
    def ext
      File.extname(filename)
    end
    
  end
end