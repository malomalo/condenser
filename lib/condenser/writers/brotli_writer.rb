# frozen_string_literal: true

require 'brotli'
require 'condenser/writers/file_writer'

# Generates a `.br` file using the Brotli algorithm with the brotli gem
class Condenser::BrotliWriter < Condenser::FileWriter

  extension '.br', content_type: 'application/brotli'

  # What mime types should we compress? This list comes from:
  # https://www.fastly.com/blog/new-gzip-settings-and-deciding-what-compress
  COMPRESSALBE_TEXT_TYPES = %w( text/html application/x-javascript text/css
    application/javascript text/javascript text/plain text/xml
    application/json application/xml image/svg+xml)
  COMPRESSALBE_FONT_TYPES = %w( application/vnd.ms-fontobject
    application/x-font-opentype application/x-font-truetype
    application/x-font-ttf font/eot font/opentype font/otf)
  COMPRESSALBE_GENERIC_TYPES = %w( image/vnd.microsoft.icon image/x-icon )

  accepts COMPRESSALBE_TEXT_TYPES, COMPRESSALBE_FONT_TYPES, COMPRESSALBE_GENERIC_TYPES

  def mode_for_mime_type(mime_type)
    if COMPRESSALBE_TEXT_TYPES.include?(mime_type)
      :text
    elsif COMPRESSALBE_FONT_TYPES.include?(mime_type)
      :font
    else
      :generic
    end
  end

  private

  def write(asset, file)
    brotli = Brotli::Writer.new(file,
      mode: mode_for_mime_type(asset.content_types.last),
      quality: 11
      # lgwin: 10-24
      # lgblock: 16-24 think bigger more compression but more mem
    )
    brotli.write(asset.source)
    brotli.finish
  end

end