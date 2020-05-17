require 'brotli'
require 'condenser/utils'

# Generates a `.br` file using the Brotli algorithm with the brotli gem
class Condenser::BrotliWriter

  # What mime types should we compress? This list comes from:
  # https://www.fastly.com/blog/new-gzip-settings-and-deciding-what-compress
  COMPRESSALBE_TEXT_TYPES = %w( text/html application/x-javascript text/css
    application/javascript text/javascript text/plain text/xml
    application/json application/xml image/svg+xml)
  COMPRESSALBE_FONT_TYPES = %w( application/vnd.ms-fontobject
    application/x-font-opentype application/x-font-truetype
    application/x-font-ttf font/eot font/opentype font/otf)
  COMPRESSALBE_GENERIC_TYPES = %w( image/vnd.microsoft.icon image/x-icon )
  
  ADDED_MIME_TYPES = ['application/brotli']
  
  attr_reader :mime_types, :added_mime_types
  
  def initialize(mime_types: nil, added_mime_types: nil)
    @mime_types = mime_types || (COMPRESSALBE_TEXT_TYPES + COMPRESSALBE_FONT_TYPES + COMPRESSALBE_GENERIC_TYPES)
    @added_mime_types = added_mime_types || ADDED_MIME_TYPES
  end
  
  def path(asset)
    "#{asset.path}.br"
  end
  
  def exist?(asset)
    ::File.exist?(path(asset))
  end
  
  def mode_for_mime_type(mime_type)
    if COMPRESSALBE_TEXT_TYPES.include?(mime_type)
      :text
    elsif COMPRESSALBE_FONT_TYPES.include?(mime_type)
      :font
    else
      :generic
    end
  end

  def call(output_directory, asset)
    filename = File.join(output_directory, "#{asset.path}.br")
    FileUtils.mkdir_p(File.dirname(filename))
    Condenser::Utils.atomic_write(filename) do |file|
      file.write(Brotli.deflate(asset.source, {
        mode: mode_for_mime_type(asset.content_types.last),
        quality: 11
        # lgwin: 10-24
        # lgblock: 16-24 think bigger more compression but more mem
      }))
    end
    
    ["#{asset.filename}.br"]
  end

end