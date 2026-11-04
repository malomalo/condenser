# frozen_string_literal: true

require 'fileutils'
require 'condenser/utils'

# Writes an asset file to disk. Subclasses set an extension, which is
# appended to the asset's path, and override #write to encode it:
#
#     class XzWriter < Condenser::FileWriter
#       extension '.xz'
#     end
class Condenser::FileWriter

  # Sets the extension appended to the asset's path with an argument, e.g.
  # `extension '.gz'` (or several, `extension '.tar.gz'`); without one,
  # returns it, or the superclass's, or nil.
  def self.extension(extension = nil)
    if extension
      @extension = extension
    else
      @extension || (superclass.extension if superclass.respond_to?(:extension))
    end
  end

  attr_reader :mime_types
  
  def initialize(mime_types: nil)
    @mime_types = mime_types || '*/*'
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