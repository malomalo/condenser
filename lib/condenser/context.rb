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

    attr_reader :environment, :filename, :source_file, :links, :dependencies, :file_dependencies, :directory_dependencies

    # The characters that make a path a glob for Dir.glob.
    GLOB = /[*?\[{]/

    def initialize(environment, source_file: nil, content_type: nil)
      @environment  = environment
      @source_file  = source_file
      @content_type = content_type
      @dependencies = Set.new
      @file_dependencies = Set.new
      @directory_dependencies = Set.new
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

    # Public: Finds the asset at a path, which may be relative to the source
    # file, and records it as a dependency. An accept type maybe given to
    # restrict the search.
    #
    #     resolve("foo.js")
    #     # => #<Condenser::Asset @filename=foo.js ...>
    #
    # Returns an Asset, or raises FileNotFound.
    def resolve(path, **kargs)
      depend_on(find_asset!(path, **kargs))
    end
    alias_method :load, :resolve

    # `depend_on` allows you to state a dependency on an asset without
    # including it.
    #
    # This is used for caching purposes. Any changes that would
    # invalidate the dependency asset will invalidate the source
    # file. Like the `depends_on` directive, +path+ may be relative to the
    # source file, and without an extension it matches the type of the
    # source file.
    #
    #     depend_on('logo.png')                  # => Asset, or raises FileNotFound
    #     depend_on('logo.png', required: false) # => Asset or nil
    #     depend_on('**/*.png')                  # => Array of Assets
    #     depend_on(asset)                       # => asset
    #
    # A glob, or a missing path that isn't required, is recorded as the path,
    # so a matching file added later invalidates the source file.
    def depend_on(path, required: true)
      if path.is_a?(Asset)
        @dependencies << asset_dependency(path)
        return path
      end

      if path.match?(GLOB)
        @dependencies << path
        return resolve_assets(path)
      end

      asset = required ? find_asset!(path) : find_asset(path)
      @dependencies << (asset ? asset_dependency(asset) : path)
      asset
    end

    # `depend_on_file` states a dependency on the contents of a file that
    # isn't processed as an asset, like a template a stylesheet is generated
    # from. See `Condenser#expand_dependency_path` for how +path+ is resolved.
    def depend_on_file(path)
      @file_dependencies << environment.expand_dependency_path(path, source_file: source_file)

      nil
    end

    # `depend_on_directory` states a dependency on the names of the files in
    # a directory that match +glob+ (a `File.fnmatch` pattern, or an Array of
    # them) and of its subdirectories, so adding or removing a matching file
    # or a subdirectory invalidates the cache. With +recursive+ it covers the
    # subdirectories too.
    def depend_on_directory(path, glob: '*', recursive: false)
      @directory_dependencies << { path: environment.expand_dependency_path(path, source_file: source_file, directory: true), glob: glob, recursive: recursive }

      nil
    end

    # `depend_on_env` allows you to state a dependency on an environment
    # variable.
    #
    # This is used for caching purposes. Any changes in the value of the
    # environment variable will invalidate the cache of the source file. It's
    # recorded as "env:KEY"; the value is checked when the cache is, so a new
    # process sees a change but a running one doesn't watch ENV.
    def depend_on_env(key)
      @dependencies << "env:#{key}"

      nil
    end

    # `link_asset` declares an external dependency on an asset without directly
    # including it, so it's compiled along with the source file. It takes the
    # same paths as `depend_on`.
    #
    # Raises FileNotFound if there's no such asset.
    def link_asset(path)
      found = depend_on(path)
      @links << (found.is_a?(Asset) ? asset_dependency(found) : path)

      nil
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
      asset = depend_on(path)
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
      data = URI.encode_www_form_component([asset.source].pack('m0'))
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

    private

    # The assets at +path+, resolved like the dependencies the asset records:
    # relative to the source file, and without an extension, of its type.
    def resolve_assets(path, accept: nil)
      dirname, basename, _, mime_types = environment.decompose_path(path, @source_file)
      accept ||= mime_types.empty? ? @content_type : mime_types
      environment.resolve(dirname ? File.join(dirname, basename) : basename, @source_file, accept: accept)
    end

    # The asset at +path+, or nil.
    def find_asset(path, **kargs)
      resolve_assets(path, **kargs).first
    end

    # The asset at +path+, or raises FileNotFound.
    def find_asset!(path, **kargs)
      find_asset(path, **kargs) or raise FileNotFound, "couldn't find file '#{path}'#{" from #{@source_file}" if @source_file}"
    end

    # The [path, accept] dependency on +asset+ with its own type.
    def asset_dependency(asset)
      dirname, basename = environment.decompose_path(asset.source_file)
      [File.join(dirname, basename), [asset.content_types]]
    end
  end
end