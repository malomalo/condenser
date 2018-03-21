require 'zlib'
require 'condenser/utils'

class Condenser
  # Generates a `.gz` file using the zlib algorithm built into
  # Ruby's standard library.
  class ZlibWriter

    # What mime types should we compress? This list comes from:
    # https://www.fastly.com/blog/new-gzip-settings-and-deciding-what-compress
    COMPRESSALBE_TYPES = %w( text/html application/x-javascript text/css
      application/javascript text/javascript text/plain text/xml
      application/json application/vnd.ms-fontobject application/x-font-opentype
      application/x-font-truetype application/x-font-ttf application/xml font/eot
      font/opentype font/otf image/svg+xml image/vnd.microsoft.icon image/x-icon)

    def skip?(asset, logger)
      target = "#{asset.path}.gz"
      if ::File.exist?(target)
        logger.debug "Skipping #{ target }, already exists"
        true
      else
        logger.info "Writing #{ target }"
        false
      end
    end

    def call(output_directory, asset)
      filename = File.join(output_directory, "#{asset.path}.gz")
      FileUtils.mkdir_p(File.dirname(filename))
      Utils.atomic_write(filename) do |file|
        gz = Zlib::GzipWriter.new(file, Zlib::BEST_COMPRESSION)
        gz.write(asset.source)
        gz.close
        # File.utime(mtime, mtime, file.path)
      end
      
      ["#{asset.filename}.gz"]
    end
    
  end
end