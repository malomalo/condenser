# frozen_string_literal: true

# An export's source map, as an asset for the writers and Condenser::Server.
class Condenser::Sourcemap

  attr_reader :path, :filename, :source, :etag

  def initialize(path:, filename:, source:, etag:)
    @path = path
    @filename = filename
    @source = source
    @etag = etag
  end

  def content_type
    'application/json'
  end

  def content_types
    [content_type]
  end

  def to_s
    @source
  end

  def length
    @source.bytesize
  end
  alias size length

  # A map has no map of its own, so it gets no SourceMap header.
  def sourcemap
    nil
  end

end
