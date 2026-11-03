# frozen_string_literal: true

require 'brotli'
require 'condenser/writers/file_writer'

# Generates a `.br` file using the Brotli algorithm with the brotli gem
class Condenser::BrotliWriter < Condenser::FileWriter

  EXTENSION = '.br'

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
  
  attr_reader :added_mime_types

  def initialize(mime_types: nil, added_mime_types: nil)
    super(mime_types: mime_types || (COMPRESSALBE_TEXT_TYPES + COMPRESSALBE_FONT_TYPES + COMPRESSALBE_GENERIC_TYPES))
    @added_mime_types = added_mime_types || ADDED_MIME_TYPES
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

  private

  def write(file, asset)
    file.write(Brotli.deflate(asset.source, {
      mode: mode_for_mime_type(asset.content_types.last),
      quality: 11
      # lgwin: 10-24
      # lgblock: 16-24 think bigger more compression but more mem
    }))
  end

end