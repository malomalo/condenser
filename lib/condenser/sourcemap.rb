# frozen_string_literal: true

# An export's source map, as an asset for the writers.
Condenser::Sourcemap = Struct.new(:path, :filename, :source, :content_types, keyword_init: true)
