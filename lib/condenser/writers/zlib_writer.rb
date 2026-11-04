# frozen_string_literal: true

require 'zlib'
require 'condenser/writers/file_writer'

# Generates a `.gz` file using the zlib algorithm built into
# Ruby's standard library.
class Condenser::ZlibWriter < Condenser::FileWriter

  extension '.gz'

  # What mime types should we compress? This list comes from:
  # https://www.fastly.com/blog/new-gzip-settings-and-deciding-what-compress
  COMPRESSALBE_TYPES = %w( text/html application/x-javascript text/css
    application/javascript text/javascript text/plain text/xml
    application/json application/vnd.ms-fontobject application/x-font-opentype
    application/x-font-truetype application/x-font-ttf application/xml font/eot
    font/opentype font/otf image/svg+xml image/vnd.microsoft.icon image/x-icon )

  ADDED_MIME_TYPES = ['application/gzip']
  
  attr_reader :added_mime_types

  def initialize(mime_types: nil, added_mime_types: nil)
    super(mime_types: mime_types || COMPRESSALBE_TYPES)
    @added_mime_types = added_mime_types || ADDED_MIME_TYPES
  end

  private

  def write(asset, file)
    gz = Zlib::GzipWriter.new(file, Zlib::BEST_COMPRESSION)
    gz.write(asset.source)
    gz.close
  end

end