# frozen_string_literal: true

require 'condenser/utils'

# Writes an asset file to disk
class Condenser::FileWriter
  
  attr_reader :mime_types
  
  def initialize(mime_types: nil)
    @mime_types = mime_types || '*/*'
  end

  def path(asset)
    asset.path
  end
  
  def exist?(asset)
    ::File.exist?(path(asset))
  end

  def call(output_directory, asset)
    filename = File.join(output_directory, asset.path)
    FileUtils.mkdir_p(File.dirname(filename))
    Condenser::Utils.atomic_write(filename) do |file|
      file.write(asset.source)
    end
    
    [asset.filename]
  end
  
end