# frozen_string_literal: true

require 'fileutils'
require 'condenser/utils'

# Writes an asset file to disk. Subclasses set the extension appended to the
# asset's path and the asset mime types they write, and override #write to
# encode the file:
#
#     class XzWriter < Condenser::FileWriter
#       extension '.xz', mime_types: 'application/x-xz'
#       mime_types 'application/javascript', 'text/css'
#     end
class Condenser::FileWriter

  # Sets the extension appended to the asset's path with an argument, e.g.
  # `extension '.gz'` (or several, `extension '.tar.gz'`), and the mime types
  # of what it adds, one per extension, e.g. for a server sending the file.
  # Without one, returns it, or the superclass's, or nil.
  def self.extension(extension = nil, mime_types: nil)
    if extension
      @extension = extension
      @output_mime_types = Array(mime_types)
    else
      @extension || (superclass.extension if superclass.respond_to?(:extension))
    end
  end

  # The mime types set with #extension, or the superclass's, or [].
  def self.output_mime_types
    @output_mime_types || (superclass.respond_to?(:output_mime_types) ? superclass.output_mime_types : [])
  end

  # Sets the asset mime types the writer writes with arguments, e.g.
  # `mime_types 'text/css', 'application/javascript'`; without them, returns
  # them, or the superclass's, or every type.
  def self.mime_types(*mime_types)
    if mime_types.empty?
      @mime_types || (superclass.respond_to?(:mime_types) ? superclass.mime_types : ['*/*'])
    else
      @mime_types = mime_types.flatten
    end
  end

  def mime_types
    self.class.mime_types
  end

  def path(asset)
    "#{asset.path}#{self.class.extension}"
  end
  
  def exist?(asset, output_directory)
    ::File.exist?(File.join(output_directory, path(asset)))
  end

  def call(asset, output_directory)
    filename = File.join(output_directory, path(asset))
    FileUtils.mkdir_p(File.dirname(filename))
    Condenser::Utils.atomic_write(filename) do |file|
      write(asset, file)
    end

    ["#{asset.filename}#{self.class.extension}"]
  end

  private

  def write(asset, file)
    file.write(asset.source)
  end

end