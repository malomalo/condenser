# frozen_string_literal: true

require 'zlib'
require 'condenser/writers/file_writer'

# Generates a `.gz` file using the zlib algorithm built into
# Ruby's standard library.
class Condenser::ZlibWriter < Condenser::FileWriter

  extension '.gz', content_type: 'application/gzip'

  # What mime types should we compress? This list comes from:
  # https://www.fastly.com/blog/new-gzip-settings-and-deciding-what-compress
  COMPRESSALBE_TYPES = %w( text/html application/x-javascript text/css
    application/javascript text/javascript text/plain text/xml
    application/json application/vnd.ms-fontobject application/x-font-opentype
    application/x-font-truetype application/x-font-ttf application/xml font/eot
    font/opentype font/otf image/svg+xml image/vnd.microsoft.icon image/x-icon )

  accepts COMPRESSALBE_TYPES

  private

  def write(asset, file)
    gz = Zlib::GzipWriter.new(file, Zlib::BEST_COMPRESSION)
    gz.write(asset.source)
    gz.close
  end

end