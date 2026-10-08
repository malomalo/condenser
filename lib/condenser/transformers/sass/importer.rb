# frozen_string_literal: true

require 'json'
require 'digest/md5'

# Resolves Sass `@import`, `@use` and `@forward` rules through the Condenser
# environment.
#
# A stylesheet's canonical URL is `condenser:/<logical filename>`. An import
# is resolved relative to the importing stylesheet first and then from the
# load paths, the same as Dart Sass. Globs (`@import "dir/*"`) import every
# match sorted by filename, and if nothing matches an npm package with a
# `style` entry is imported.
#
# Dart Sass first asks to resolve an import relative to the importing
# stylesheet without saying which stylesheet that is; those requests are
# declined so imports are always resolved with `context.containing_url`.
class Condenser::Sass::Importer
  SCHEME = 'condenser'
  NPM_SCHEME = 'condenser-npm'
  GLOB_SCHEME = 'condenser-glob'
  GLOB_ENTRY_SCHEME = 'condenser-glob-entry'
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
  end

  # The canonical URL of the stylesheet being compiled.
  def url
    root = @environment.path.find { |p| @input[:source_file].start_with?(File.join(p, '')) }
    name = root ? @input[:source_file].delete_prefix(File.join(root, '')) : @input[:filename]
    url = self.class.url(SCHEME, name)
    @source_files[url] = @input[:source_file]
    url
  end

  def canonicalize(url, context)
    scheme, raw = parse(url.delete_suffix('?entry'))
    if scheme == GLOB_ENTRY_SCHEME
      return self.class.url(SCHEME, raw)
    elsif context.containing_url.nil?
      return
    elsif scheme.nil?
      containing_scheme, containing_name = parse(context.containing_url)
      if containing_scheme == SCHEME && !raw.start_with?('/')
        relative = expand_path(File.join(File.dirname(containing_name), raw))
        name, assets = relative, resolve(relative) if relative
      end
      if (assets.nil? || assets.empty?) && !raw.start_with?('../')
        load_path_name = raw.start_with?('/') ? raw : expand_path(raw)
        name, assets = load_path_name, resolve(load_path_name) if load_path_name != relative
      end
    else
      return
    end

    assets = assets.reject { |a| a.source_file == @source_files[context.containing_url] } if assets
    if assets.nil? || assets.empty?
      npm_style(raw) unless raw.start_with?('../')
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
      { contents: asset.source, syntax: File.extname(asset.source_file) == '.sass' ? :indented : :scss }
    end
  end

  private

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
