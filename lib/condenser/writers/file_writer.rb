# frozen_string_literal: true

require 'fileutils'
require 'condenser/utils'

# Writes an asset file to disk. Subclasses set EXTENSION, which is appended
# to the asset's path, and override #write to encode it.
class Condenser::FileWriter

  EXTENSION = nil

  attr_reader :mime_types
  
  def initialize(mime_types: nil)
    @mime_types = mime_types || '*/*'
  end

  def path(asset)
    "#{asset.path}#{self.class::EXTENSION}"
  end
  
  def exist?(output_directory, asset)
    ::File.exist?(File.join(output_directory, path(asset)))
  end

  def call(output_directory, asset)
    filename = File.join(output_directory, path(asset))
    FileUtils.mkdir_p(File.dirname(filename))
    Condenser::Utils.atomic_write(filename) do |file|
      write(file, asset)
    end

    ["#{asset.filename}#{self.class::EXTENSION}"]
  end

  private

  def write(file, asset)
    file.write(asset.source)
  end

end