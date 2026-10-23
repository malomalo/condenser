# frozen_string_literal: true

require 'json'
require 'digest/md5'

# Resolves Sass imports through the Condenser environment. Every stylesheet,
# the entry included, gets a `condenser:` URL, and Dart Sass's tries at
# resolving a URL relative to one are declined, so bare URLs use the load paths.
# npm stylesheets get a `condenser-npm:` URL and do resolve relative URLs, the
# way Sass does for files, so their partials load from next to them.
class Condenser::Sass::Importer
  SCHEME = 'condenser'
  NPM_SCHEME = 'condenser-npm'
  GLOB_SCHEME = 'condenser-glob'
  GLOB_ENTRY_SCHEME = 'condenser-glob-entry'
  RELATIVE_SCHEME = 'condenser-relative'
  # Stops Dart Sass treating glob entries ending in `.css` as plain CSS imports
  ENTRY_QUERY = '?entry'
  EXTENSIONS = %w(.sass .scss .css).freeze
  SYNTAXES = { 'text/sass' => :indented, 'text/scss' => :scss, 'text/css' => :css }.freeze
  FILE_SYNTAXES = { '.sass' => :indented, '.scss' => :scss, '.css' => :css }.freeze
  # The `exports` conditions Dart Sass's Node package importer matches
  EXPORT_CONDITIONS = %w(sass style default).freeze

  def self.url(scheme, name)
    "#{scheme}:/#{escape(name)}"
  end

  # Percent-encodes +name+ for a URL path, including `!`, `?` and `#`.
  def self.escape(name)
    name.gsub(%r{[^A-Za-z0-9\-._~/*$&'()+,;=:@]}) { |c| c.bytes.map { |b| format('%%%02X', b) }.join }
  end

  def initialize(environment, input)
    @environment = environment
    @input = input
    @accept = EXTENSIONS.map { |x| @environment.extensions[x] }
    @assets = {}
    @source_files = {}
    @sources = {}
    @npm_files = {}

    root = @environment.path.find { |p| @input[:source_file].start_with?(File.join(p, '')) }
    @name = root ? @input[:source_file].delete_prefix(File.join(root, '')) : @input[:filename]
    @url = self.class.url(SCHEME, @name)
    @source_files[@url] = @input[:source_file]
  end

  # The canonical URL of the stylesheet being compiled.
  attr_reader :url

  # The source of the stylesheet being compiled, with its relative imports
  # rewritten.
  def source(syntax)
    rewrite_relative_imports(@input[:source], @name, syntax)
  end

  def canonicalize(url, context)
    scheme, path = parse(url)
    case scheme
    when GLOB_ENTRY_SCHEME
      return self.class.url(SCHEME, decode(path.delete_suffix(ENTRY_QUERY)))
    when RELATIVE_SCHEME
      importer, name = path.split('!/', 2).map { |part| decode(part) }
      importer_file = @source_files[self.class.url(SCHEME, importer)]
    when NPM_SCHEME
      # A URL relative to an npm stylesheet, resolved by Dart Sass. nil if
      # there's no such file.
      return if @environment.npm_path.nil?
      file = sass_file(File.join(@environment.npm_path, decode(path)))
      return npm_url(file) if file
      return
    when nil
      return if context.containing_url.nil?
      name = expand_path(decode(path))
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
      @sources[glob] = assets.map { |a| "@import \"#{self.class.url(GLOB_ENTRY_SCHEME, a.filename)}#{ENTRY_QUERY}\";\n" }.join
      glob
    end
  end

  def load(canonical_url)
    if source = @sources[canonical_url]
      { contents: source, syntax: :scss }
    elsif (file = @npm_files[canonical_url])
      { contents: File.read(file), syntax: FILE_SYNTAXES.fetch(File.extname(file)) }
    else
      asset = @assets[canonical_url]
      syntax = SYNTAXES.fetch(asset.content_type, :scss)
      { contents: rewrite_relative_imports(asset.source, asset.filename, syntax), syntax: syntax }
    end
  end

  private

  # Rewrites relative URLs to `condenser-relative:/<importing file>!/<resolved
  # name>`. The resolved name comes last since `@use` takes its namespace from
  # the URL's basename.
  def rewrite_relative_imports(source, name, syntax)
    return source if syntax == :css

    Condenser::Sass::RelativeImports.rewrite(source, indented: syntax == :indented) do |url|
      if (path = expand_path(File.join(File.dirname(name), url)))
        "#{self.class.url(RELATIVE_SCHEME, name)}!/#{self.class.escape(path)}"
      end
    end
  end

  def canonical_url(asset)
    url = self.class.url(SCHEME, asset.filename)
    @assets[url] = asset
    @source_files[url] = asset.source_file
    url
  end

  # Splits +url+ into its scheme (nil if it has none) and the rest.
  def parse(url)
    url =~ %r{\A([a-z][a-z0-9+\-.]*):/?(.*)\z}i ? [$1, $2] : [nil, url]
  end

  def decode(path)
    URI.decode_uri_component(path)
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
    assets = @environment.resolve(name, accept: @accept)
    assets.group_by(&:source_file).map { |_, a| a.min_by { |x| @accept.index(x.content_type) || @accept.size } }.sort_by(&:filename)
  end

  # The stylesheet of the npm package +name+, chosen as Dart Sass's Node
  # package importer does: the `sass`, `style` or `default` condition of the
  # package's root export, then its `sass` field, its `style` field and its
  # index file.
  def npm_style(name)
    return if @environment.npm_path.nil?

    [File.join(@environment.npm_path, name), File.join(@environment.npm_path, 'node_modules', name)].each do |dir|
      package = File.join(dir, 'package.json')
      next unless File.exist?(package)

      manifest = JSON.parse(File.read(package))
      paths = [npm_export(manifest['exports']), manifest['sass'], manifest['style']]
      file = paths.grep(String).map { |path| File.expand_path(path, dir) }.find { |f| FILE_SYNTAXES.key?(File.extname(f)) && File.file?(f) }
      file ||= sass_file(File.join(dir, 'index'), index: false)
      return npm_url(file) if file
    end
    nil
  end

  # The target of a package's root export for the `sass`, `style` or `default`
  # condition, or nil. Targets Sass can't load are skipped.
  def npm_export(exports)
    case exports
    when String
      exports if FILE_SYNTAXES.key?(File.extname(exports))
    when Array
      exports.lazy.filter_map { |e| npm_export(e) }.first
    when Hash
      return npm_export(exports['.']) if exports.keys.any? { |k| k.start_with?('.') }
      exports.lazy.filter_map { |k, v| npm_export(v) if EXPORT_CONDITIONS.include?(k) }.first
    end
  end

  # The file Sass loads for +path+: the file or its partial, trying each
  # extension if it has none, and then its index file.
  def sass_file(path, index: true)
    has_extension = FILE_SYNTAXES.key?(File.extname(path))
    names = has_extension ? [path] : FILE_SYNTAXES.keys.map { |x| path + x }
    file = names.flat_map { |n| [n, File.join(File.dirname(n), "_#{File.basename(n)}")] }.find { |f| File.file?(f) }
    file || (sass_file(File.join(path, 'index'), index: false) if index && !has_extension)
  end

  # Records +file+ as a dependency and returns its `condenser-npm:` URL.
  def npm_url(file)
    url = self.class.url(NPM_SCHEME, file.delete_prefix(File.join(@environment.npm_path, '')))
    unless @npm_files.key?(url)
      @input[:process_dependencies] << [file, @accept.map { |i| [i] }]
      @npm_files[url] = file
      @source_files[url] = file
    end
    url
  end
end
