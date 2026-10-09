# frozen_string_literal: true

require 'json'
require 'digest/md5'

# Resolves Sass `@import`, `@use` and `@forward` rules through the Condenser
# environment, the same way the sassc importer did: URLs starting with `./` or
# `../` resolve next to the importing stylesheet and other URLs from the load
# paths. Globs (`@import "dir/*"`) import every match sorted by filename, and
# if nothing matches an npm package with a `style` entry is imported.
#
# A stylesheet's canonical URL is `condenser:/<logical filename>`. Dart Sass
# drops a leading `./` before calling an importer, so before a stylesheet is
# handed to Dart Sass its relative URLs are rewritten to
# `condenser-relative:/<resolved name>` (see Condenser::Sass::RelativeImports).
# Dart Sass's requests to resolve a URL relative to the importing stylesheet
# are declined, so other URLs resolve from the load paths.
class Condenser::Sass::Importer
  SCHEME = 'condenser'
  NPM_SCHEME = 'condenser-npm'
  GLOB_SCHEME = 'condenser-glob'
  GLOB_ENTRY_SCHEME = 'condenser-glob-entry'
  RELATIVE_SCHEME = 'condenser-relative'
  EXTENSIONS = %w(.sass .scss .css).freeze

  def self.url(scheme, name)
    "#{scheme}:/" + name.gsub(%r{[^A-Za-z0-9\-._~/*!$&'()+,;=:@]}) { |c| c.bytes.map { |b| format('%%%02X', b) }.join }
  end

  def initialize(environment, input)
    @environment = environment
    @input = input
    @accept = EXTENSIONS.map { |x| @environment.extensions[x] }
    @assets = {}
    @source_files = {}
    @sources = {}
    @relative = []
  end

  # The canonical URL of the stylesheet being compiled (call before #source).
  def url
    root = @environment.path.find { |p| @input[:source_file].start_with?(File.join(p, '')) }
    name = root ? @input[:source_file].delete_prefix(File.join(root, '')) : @input[:filename]
    @name = name
    url = self.class.url(SCHEME, name)
    @source_files[url] = @input[:source_file]
    url
  end

  # The source of the stylesheet being compiled, with its relative imports
  # rewritten.
  def source(syntax)
    rewrite_relative_imports(@input[:source], @name, @input[:source_file], syntax)
  end

  def canonicalize(url, context)
    scheme, raw = parse(url.sub(/\?[^?]*\z/, ''))
    case scheme
    when GLOB_ENTRY_SCHEME
      return self.class.url(SCHEME, raw)
    when RELATIVE_SCHEME
      name = raw
      importer_file = @relative[url[/\?(\d+)\z/, 1].to_i]
    when nil
      return if context.containing_url.nil?
      name = expand_path(raw)
      return if name.nil?
      importer_file = @source_files[context.containing_url]
    else
      return
    end

    assets = resolve(name).reject { |a| a.source_file == importer_file }
    if assets.empty?
      npm_style(name)
    elsif assets.size == 1
      canonical_url(assets.first)
    else
      assets.each { |a| canonical_url(a) }
      glob = self.class.url(GLOB_SCHEME, name) + "?#{Digest::MD5.hexdigest(assets.map(&:filename).join(','))}"
      # The query stops Dart Sass treating `.css` URLs as plain CSS imports
      @sources[glob] = assets.map { |a| "@import \"#{self.class.url(GLOB_ENTRY_SCHEME, a.filename)}?entry\";\n" }.join
      glob
    end
  end

  def load(canonical_url)
    if source = @sources[canonical_url]
      { contents: source, syntax: :scss }
    else
      asset = @assets[canonical_url]
      syntax = File.extname(asset.source_file) == '.sass' ? :indented : :scss
      { contents: rewrite_relative_imports(asset.source, asset.filename, asset.source_file, syntax), syntax: syntax }
    end
  end

  private

  def rewrite_relative_imports(source, name, source_file, syntax)
    Condenser::Sass::RelativeImports.rewrite(source, indented: syntax == :indented) do |url|
      if (path = expand_path(File.join(File.dirname(name), url)))
        @relative << source_file
        self.class.url(RELATIVE_SCHEME, path) + "?#{@relative.size - 1}"
      end
    end
  end

  def canonical_url(asset)
    url = self.class.url(SCHEME, asset.filename)
    @assets[url] = asset
    @source_files[url] = asset.source_file
    url
  end

  def parse(url)
    if url =~ %r{\A([a-z][a-z0-9+\-.]*):/?(.*)\z}i
      [$1, URI.decode_uri_component($2)]
    else
      [nil, URI.decode_uri_component(url)]
    end
  end

  # Normalizes a logical path, returning nil if it points above the root.
  def expand_path(path)
    path.split('/').each_with_object([]) do |segment, parts|
      case segment
      when '', '.' then next
      when '..' then return nil if parts.pop.nil?
      else parts << segment
      end
    end.join('/')
  end

  def resolve(name)
    @input[:process_dependencies] << [name, @accept.map { |i| [i] }]
    @environment.resolve(name, accept: @accept)
  end

  def npm_style(name)
    return if @environment.npm_path.nil?

    [File.join(@environment.npm_path, name), File.join(@environment.npm_path, 'node_modules', name)].each do |dir|
      package = File.join(dir, 'package.json')
      next unless File.exist?(package)

      style = JSON.parse(File.read(package))['style']
      next unless style

      file = File.expand_path(style, dir)
      url = self.class.url(NPM_SCHEME, file.delete_prefix(File.join(@environment.npm_path, '')))
      @sources[url] = File.read(file)
      return url
    end
    nil
  end
end
