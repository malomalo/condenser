require 'zlib'
require 'condenser/utils'

# Generates a `.gz` file using the zlib algorithm built into
# Ruby's standard library.
class Condenser::ZlibWriter

  # What mime types should we compress? This list comes from:
  # https://www.fastly.com/blog/new-gzip-settings-and-deciding-what-compress
  COMPRESSALBE_TYPES = %w( text/html application/x-javascript text/css
    application/javascript text/javascript text/plain text/xml
    application/json application/vnd.ms-fontobject application/x-font-opentype
    application/x-font-truetype application/x-font-ttf application/xml font/eot
    font/opentype font/otf image/svg+xml image/vnd.microsoft.icon image/x-icon)

  ADDED_MIME_TYPES = ['application/gzip']
  
  attr_reader :mime_types, :added_mime_types
  
  def initialize(mime_types: nil, added_mime_types: nil)
    @mime_types = mime_types || COMPRESSALBE_TYPES
    @added_mime_types = added_mime_types || ADDED_MIME_TYPES
  end
  
  def exist?(asset)
    ::File.exist?("#{asset.path}.gz")
  end

  def call(output_directory, asset)
    filename = File.join(output_directory, "#{asset.path}.gz")
    FileUtils.mkdir_p(File.dirname(filename))
    Condenser::Utils.atomic_write(filename) do |file|
      gz = Zlib::GzipWriter.new(file, Zlib::BEST_COMPRESSION)
      gz.write(asset.source)
      gz.close
      # File.utime(mtime, mtime, file.path)
    end
    
    ["#{asset.filename}.gz"]
  end

end