# frozen_string_literal: true

require 'fileutils'
require 'condenser/utils'

# Writes an asset file to disk. Subclasses set the extension appended to the
# asset's path and the asset mime types they write, and override #write to
# encode the file:
#
#     class XzWriter < Condenser::FileWriter
#       extension '.xz', content_type: 'application/x-xz'
#       accepts 'application/javascript', 'text/css'
#     end
class Condenser::FileWriter

  # Sets the extension appended to the asset's path with an argument, e.g.
  # `extension '.gz', content_type: 'application/gzip'`, and the content type
  # of what it adds, e.g. for a server sending the file. Several extensions
  # take one content type each: `extension '.tar.gz', content_type:
  # ['application/x-tar', 'application/gzip']`. Without an argument, returns
  # the extension, or the superclass's, or nil.
  def self.extension(extension = nil, content_type: nil)
    if extension
      raise ArgumentError, "extension #{extension.inspect} needs a content_type:" if content_type.nil?
      @extension = extension
      @content_type = content_type
    else
      @extension || (superclass.extension if superclass.respond_to?(:extension))
    end
  end

  # The content type set with #extension, or the superclass's, or nil.
  def self.content_type
    @content_type || (superclass.content_type if superclass.respond_to?(:content_type))
  end

  # Sets the asset mime types the writer writes with arguments, e.g.
  # `accepts 'text/css', 'application/javascript'`; without them, returns
  # them, or the superclass's, or every type.
  def self.accepts(*mime_types)
    if mime_types.empty?
      @accepts || (superclass.respond_to?(:accepts) ? superclass.accepts : ['*/*'])
    else
      @accepts = mime_types.flatten
    end
  end

  # The asset mime types register_writer registers the writer for.
  def accepts
    self.class.accepts
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

  # Writes the asset to +file+; leave it open, Utils.atomic_write closes it.
  def write(asset, file)
    file.write(asset.source)
  end

end