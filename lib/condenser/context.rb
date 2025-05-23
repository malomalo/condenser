# frozen_string_literal: true

require 'set'
require 'condenser/errors'

class Condenser
  # They are typically accessed by ERB templates. You can mix in custom helpers
  # by injecting them into `Environment#context_class`. Do not mix them into
  # `Context` directly.
  #
  #     environment.context_class.class_eval do
  #       include MyHelper
  #       def asset_url; end
  #     end
  #
  #     <%= asset_url "foo.png" %>
  #
  # The `Context` also collects dependencies declared by
  # assets. See `DirectiveProcessor` for an example of this.
  class Context
    # Internal: Proxy for ENV that keeps track of the environment variables used
    class ENVProxy < SimpleDelegator
      def initialize(context)
        @context = context
        super(ENV)
      end

      def [](key)
        @context.depend_on_env(key)
        super
      end

      def fetch(key, *)
        @context.depend_on_env(key)
        super
      end
    end

    attr_reader :environment, :filename, :links, :dependencies

    def initialize(environment)
      @environment  = environment
      @dependencies = Set.new
      @links = Set.new
    end

    def metadata
      {
        links: @links,
        dependencies: @dependencies
      }
    end

    def env_proxy
      ENVProxy.new(self)
    end

    # Returns the environment path that contains the file.
    #
    # If `app/javascripts` and `app/stylesheets` are in your path, and
    # current file is `app/javascripts/foo/bar.js`, `load_path` would
    # return `app/javascripts`.
    attr_reader :load_path
    alias_method :root_path, :load_path

    # Returns logical path without any file extensions.
    #
    #     'app/javascripts/application.js'
    #     # => 'application'
    #
    attr_reader :logical_path

    # Returns content type of file
    #
    #     'application/javascript'
    #     'text/css'
    #
    attr_reader :content_type

    # Public: Given a logical path, `resolve` will find and return an Asset URI.
    # Relative paths will also be resolved. An accept type maybe given to
    # restrict the search.
    #
    #     resolve("foo.js")
    #     # => "file:///path/to/app/javascripts/foo.js?type=application/javascript"
    #
    #     resolve("./bar.js")
    #     # => "file:///path/to/app/javascripts/bar.js?type=application/javascript"
    #
    # path   - String logical or absolute path
    # accept - String content accept type
    #
    # Returns an Asset URI String.
    def resolve(path, **kargs)
      uri, deps = environment.resolve!(path, @dirname, **kargs)
      @dependencies.merge(deps)
      uri
    end

    # Public: Load Asset by AssetURI and track it as a dependency.
    #
    # uri - AssetURI
    #
    # Returns Asset.
    def load(uri)
      asset = environment.load(uri)
      @dependencies.merge(asset.metadata[:dependencies])
      asset
    end

    # `depend_on` allows you to state a dependency on a file without
    # including it.
    #
    # This is used for caching purposes. Any changes that would
    # invalidate the dependency asset will invalidate the source
    # file.
    def depend_on(path)
      d = environment.decompose_path(path)
      @dependencies << [File.join(*d[0], d[1]), [d[3]]]

      nil
    end

    # `depend_on_env` allows you to state a dependency on an environment
    # variable.
    #
    # This is used for caching purposes. Any changes in the value of the
    # environment variable will invalidate the cache of the source file.
    def depend_on_env(key)
      @dependencies << "env:#{key}"
    end

    # `link_asset` declares an external dependency on an asset without directly
    # including it. The target asset is returned from this function making it
    # easy to construct a link to it.
    #
    # Returns an Asset or nil.
    def link_asset(path)
      depend_on(path)
      @links << path
    end

    # Returns a `data:` URI with the contents of the asset at the specified
    # path, and marks that path as a dependency of the current file.
    #
    # Uses URI encoding for SVG files, base64 encoding for all the other files.
    #
    # Use `asset_data_uri` from ERB with CSS or JavaScript assets:
    #
    #     #logo { background: url(<%= asset_data_uri 'logo.png' %>) }
    #
    #     $('<img>').attr('src', '<%= asset_data_uri 'avatar.jpg' %>')
    #
    def asset_data_uri(path)
      asset = depend_on_asset(path)
      if asset.content_type == 'image/svg+xml'
        svg_asset_data_uri(asset)
      else
        base64_asset_data_uri(asset)
      end
    end

    # Expands logical path to full url to asset.
    #
    # NOTE: This helper is currently not implemented and should be
    # customized by the application. Though, in the future, some
    # basics implemention may be provided with different methods that
    # are required to be overridden.
    def asset_path(path, options = {})
      message = <<-EOS
Custom asset_path helper is not implemented

Extend your environment context with a custom method.

    environment.context_class.class_eval do
      def asset_path(path, options = {})
      end
    end
      EOS
      raise LoadError, message # Rack does not catch NotImplementedError
    end

    # Expand logical image asset path.
    def image_path(path)
      asset_path(path, type: :image)
    end

    # Expand logical video asset path.
    def video_path(path)
      asset_path(path, type: :video)
    end

    # Expand logical audio asset path.
    def audio_path(path)
      asset_path(path, type: :audio)
    end

    # Expand logical font asset path.
    def font_path(path)
      asset_path(path, type: :font)
    end

    # Expand logical javascript asset path.
    def javascript_path(path)
      asset_path(path, type: :javascript)
    end

    # Expand logical stylesheet asset path.
    def stylesheet_path(path)
      asset_path(path, type: :stylesheet)
    end

    protected

    # Returns a URI-encoded data URI (always "-quoted).
    def svg_asset_data_uri(asset)
      svg = asset.source.dup
      optimize_svg_for_uri_escaping!(svg)
      data = URI.encode_www_form_component(svg)
      optimize_quoted_uri_escapes!(data)
      "\"data:#{asset.content_type};charset=utf-8,#{data}\""
    end

    # Returns a Base64-encoded data URI.
    def base64_asset_data_uri(asset)
      data = URI.encode_www_form_component(EncodingUtils.base64(asset.source))
      "data:#{asset.content_type};base64,#{data}"
    end

    # Optimizes an SVG for being URI-escaped.
    #
    # This method only performs these basic but crucial optimizations:
    # * Replaces " with ', because ' does not need escaping.
    # * Removes comments, meta, doctype, and newlines.
    # * Collapses whitespace.
    def optimize_svg_for_uri_escaping!(svg)
      # Remove comments, xml meta, and doctype
      svg.gsub!(/<!--.*?-->|<\?.*?\?>|<!.*?>/m, '')
      # Replace consecutive whitespace and newlines with a space
      svg.gsub!(/\s+/, ' ')
      # Collapse inter-tag whitespace
      svg.gsub!('> <', '><')
      # Replace " with '
      svg.gsub!(/([\w:])="(.*?)"/, "\\1='\\2'")
      svg.strip!
    end

    # Un-escapes characters in the given URI-escaped string that do not need
    # escaping in "-quoted data URIs.
    def optimize_quoted_uri_escapes!(escaped)
      escaped.gsub!('%3D', '=')
      escaped.gsub!('%3A', ':')
      escaped.gsub!('%2F', '/')
      escaped.gsub!('%27', "'")
      escaped.tr!('+', ' ')
    end
  end
end