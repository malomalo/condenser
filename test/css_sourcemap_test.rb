require 'test_helper'
require 'rack/builder'
require 'rack/test'
require 'rack/lint'

class CSSSourcemapTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include SourcemapHelpers

  # Rewrites the CSS without updating the map, so it clears it.
  class RewritingMinifier < Condenser::Processor
    def call(environment, input)
      input[:source] = "/* minified */\n" + input[:source]
      input[:sourcemap] = nil
    end
  end

  # Leaves the CSS and its map as they are.
  class NoopMinifier < Condenser::Processor
    def call(environment, input)
    end
  end

  def setup
    super
    @dir = Dir.mktmpdir
    @packages = []
    file 'app.scss', <<~SCSS
      @use "partials/colors";

      // A comment, so the source lines differ from the CSS's.
      body {
        color: colors.$red;
        .nested { margin: 0; }
      }
    SCSS
    file 'partials/colors.scss', <<~SCSS
      $red: red;
      .from-partial {
        padding: 1px;
      }
    SCSS
  end

  def teardown
    @packages.each { |package| FileUtils.rm_rf(package) }
    FileUtils.remove_entry(@dir, true)
    FileUtils.remove_entry(@cache_dir, true) if @cache_dir
    super
  end

  # sourcemap is set only through Condenser.new, so passing it replaces @env.
  # The default minifier, LightningCSSMinifier, clears the map, so it's
  # unregistered unless the test is about it.
  def css(sourcemap: nil, minifier: false)
    @env = environment(sourcemap: sourcemap) unless sourcemap.nil?
    @env.unregister_minifier('text/css') unless minifier
  end

  def environment(sourcemap:, cache: nil)
    env = Condenser.new(@path, logger: @env.logger, npm_path: @npm_dir, base: @path, listen: false, sourcemap: sourcemap, cache: cache)
    env.unregister_writer(Condenser::ZlibWriter)
    env.unregister_writer(Condenser::BrotliWriter)
    env
  end

  def app
    server = Condenser::Server.new(@env)
    Rack::Lint.new(Rack::Builder.new { map("/assets") { run server } })
  end

  CSS = <<~CSS
    .from-partial {
      padding: 1px;
    }

    body {
      color: red;
    }
    body .nested {
      margin: 0;
    }
  CSS

  test 'sourcemap: false compiles Sass without a map' do
    css
    export = assert_exported_file 'app.css', 'text/css', CSS

    assert_nil @env.find('app.css').sourcemap
    assert_nil export.sourcemap
    assert_nil export.sourcemap_path
    assert_nil export.to_json.fetch(:sourcemap)
    assert_not_includes export.source, 'sourceMappingURL'
  end

  test 'sourcemap: true exports a map and links it from the stylesheet' do
    css(sourcemap: true)
    export = @env.find('app.css').export
    map = JSON.parse(export.sourcemap)

    assert_equal 3, map['version']
    assert_equal ['partials/colors.scss', 'app.scss'], map['sources']
    assert_equal File.read(File.join(@path, 'partials/colors.scss')), map['sourcesContent'][0]
    assert_equal File.read(File.join(@path, 'app.scss')), map['sourcesContent'][1]

    assert_equal "#{export.path}.map", export.sourcemap_path
    assert_equal "#{CSS}/*# sourceMappingURL=#{File.basename(export.path)}.map */\n", export.source
    assert_equal @env.digestor.digest(export.source), export.digest
  end

  test 'sourcemap: :linked exports a map with the comment' do
    css(sourcemap: :linked)
    export = @env.find('app.css').export

    assert_equal ['partials/colors.scss', 'app.scss'], JSON.parse(export.sourcemap)['sources']
    assert export.source.end_with?("}\n/*# sourceMappingURL=#{File.basename(export.path)}.map */\n")
  end

  test 'sourcemap: :headers exports a map without the comment' do
    css(sourcemap: :headers)
    export = @env.find('app.css').export

    assert_equal ['partials/colors.scss', 'app.scss'], JSON.parse(export.sourcemap)['sources']
    assert_equal "#{export.path}.map", export.sourcemap_path
    assert_equal CSS.chomp, export.source
  end

  test 'the mappings point back to the sources' do
    css(sourcemap: true)
    export = @env.find('app.css').export
    map = JSON.parse(export.sourcemap)

    assert_equal ['partials/colors.scss', 1, 0], original_position(export.source, map, '.from-partial')
    assert_equal ['partials/colors.scss', 2, 2], original_position(export.source, map, 'padding')
    assert_equal ['app.scss', 3, 0], original_position(export.source, map, 'body {')
    assert_equal ['app.scss', 4, 2], original_position(export.source, map, 'color: red')
    assert_equal ['app.scss', 5, 2], original_position(export.source, map, 'body .nested')
    assert_equal ['app.scss', 5, 12], original_position(export.source, map, 'margin')
  end

  test 'sources from @import, relative imports and the indented syntax are logical paths' do
    @env.register_mime_type 'text/sass', extensions: %w(.sass)
    @env.register_transformer 'text/sass', 'text/css', Condenser::SassTransformer.new
    file 'pages/admin/index.scss', <<~SCSS
      @import './users';
      @import "shared";
    SCSS
    file 'pages/admin/users.sass', ".users\n  color: blue\n"
    file 'shared.scss', ".shared { color: green; }\n"

    css(sourcemap: :headers)
    export = @env.find('pages/admin/index.css').export
    map = JSON.parse(export.sourcemap)

    assert_equal ".users {\n  color: blue;\n}\n\n.shared {\n  color: green;\n}", export.source
    assert_equal ['pages/admin/users.sass', 'shared.scss'], map['sources']
    assert_equal ['pages/admin/users.sass', 1, 2], original_position(export.source, map, 'color: blue')
    assert_equal ['shared.scss', 0, 10], original_position(export.source, map, 'color: green')
  end

  test 'npm sources are relative to the npm path' do
    package = File.join(@npm_dir, 'node_modules', 'condenser-sass-sourcemap-test')
    @packages << package
    FileUtils.mkdir_p(package)
    File.write(File.join(package, 'package.json'), JSON.generate(name: 'condenser-sass-sourcemap-test', sass: '_index.scss'))
    File.write(File.join(package, '_index.scss'), ".from-npm {\n  border: 0;\n}\n")
    file 'npm.scss', <<~SCSS
      @use "condenser-sass-sourcemap-test";
      .own { color: red; }
    SCSS

    css(sourcemap: :headers)
    export = @env.find('npm.css').export
    map = JSON.parse(export.sourcemap)

    assert_equal ['node_modules/condenser-sass-sourcemap-test/_index.scss', 'npm.scss'], map['sources']
    assert_equal ['node_modules/condenser-sass-sourcemap-test/_index.scss', 1, 2], original_position(export.source, map, 'border')
  end

  test 'sass_config cannot set the source map options' do
    %i(source_map source_map_include_sources).each do |key|
      error = assert_raises(ArgumentError) { Condenser::ScssTransformer.new(sass_config: { key => true }) }
      assert_equal "sass_config can't include :#{key}, condenser sets it from the environment's sourcemap setting", error.message
    end
  end

  test 'sourcemap is in the cache key, so a cached stylesheet is reprocessed with a map' do
    @cache_dir = Dir.mktmpdir
    without = environment(sourcemap: false, cache: Condenser::Cache::FileStore.new(@cache_dir)).find('app.css')
    without.process
    with = environment(sourcemap: true, cache: Condenser::Cache::FileStore.new(@cache_dir)).find('app.css')

    assert_not_equal without.cache_key, with.cache_key
    assert_nil without.sourcemap
    assert_equal ['partials/colors.scss', 'app.scss'], JSON.parse(with.sourcemap)['sources']
    assert_equal without.source, with.source
  end

  test 'the etag and output change between values without an exporter or minifier' do
    exports = [false, true, :linked, :headers].to_h do |value|
      env = environment(sourcemap: value)
      env.unregister_minifier('text/css')
      [value, env.find('app.css').export]
    end

    assert_equal 4, exports.values.map(&:etag).uniq.size
    assert_includes exports[:linked].source, 'sourceMappingURL'
    assert_not_includes exports[:headers].source, 'sourceMappingURL'
    assert_equal exports[:headers].source, exports[false].source
  end

  test 'sourcemap: false leaves the pipeline digests of unexported types alone' do
    assert_nil @env.export_pipeline_digest('image/png')
    assert_nil environment(sourcemap: false).export_pipeline_digest('image/png')
    assert_not_nil environment(sourcemap: :headers).export_pipeline_digest('image/png')
  end

  test 'LightningCSSMinifier, the default minifier, exports no map' do
    css(sourcemap: true, minifier: true)
    export = @env.find('app.css').export

    assert_instance_of Condenser::LightningCSSMinifier, @env.minifier_for('text/css')
    assert_equal ['partials/colors.scss', 'app.scss'], JSON.parse(@env.find('app.css').sourcemap)['sources']
    assert_equal '.from-partial{padding:1px}body{color:red}body .nested{margin:0}', export.source
    assert_nil export.sourcemap
    assert_nil export.sourcemap_path
    assert_nil export.to_json.fetch(:sourcemap)
  end

  test 'LightningCSSExporter clears the map' do
    css(sourcemap: true)
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(targets: { safari: 12 }))
    export = @env.find('app.css').export

    assert_equal ".from-partial {\n  padding: 1px;\n}\n\nbody {\n  color: red;\n}\n\nbody .nested {\n  margin: 0;\n}\n", export.source
    assert_nil export.sourcemap
    assert_not_includes export.source, 'sourceMappingURL'
  end

  test 'SassMinifier clears the map' do
    css(sourcemap: true)
    @env.register_minifier('text/css', Condenser::SassMinifier.new)
    export = @env.find('app.css').export

    assert_equal '.from-partial{padding:1px}body{color:red}body .nested{margin:0}', export.source
    assert_nil export.sourcemap
  end

  test 'a minifier that clears the map exports none' do
    css(sourcemap: true)
    @env.register_minifier('text/css', RewritingMinifier.new)
    export = @env.find('app.css').export

    assert export.source.start_with?("/* minified */\n")
    assert_nil export.sourcemap
    assert_not_includes export.source, 'sourceMappingURL'
  end

  test 'a minifier that leaves the map keeps it' do
    css(sourcemap: true)
    @env.register_minifier('text/css', NoopMinifier.new)
    export = @env.find('app.css').export

    assert_equal ['partials/colors.scss', 'app.scss'], JSON.parse(export.sourcemap)['sources']
    assert export.source.end_with?("\n/*# sourceMappingURL=#{File.basename(export.path)}.map */\n")
  end

  test 'CSSMediaCombinerProcessor clears the map' do
    css(sourcemap: true)
    @env.register_postprocessor('text/css', Condenser::CSSMediaCombinerProcessor.new)
    file 'media.scss', <<~SCSS
      @media (min-width: 100px) { .a { color: red; } }
      .b { color: blue; }
      @media (min-width: 100px) { .c { color: green; } }
    SCSS

    asset = @env.find('media.css')
    assert_equal ".b {\n  color: blue;\n}@media (min-width: 100px) {\n  .a {\n    color: red;\n  }\n\n  .c {\n    color: green;\n  }\n}", asset.source.strip
    assert_nil asset.sourcemap
    assert_nil asset.export.sourcemap
  end

  test 'PurgeCSSProcessor clears the map' do
    css(sourcemap: true)
    @env.register_postprocessor('text/css', Condenser::PurgeCSSProcessor.new(@npm_dir, content: [File.join(@path, '**/*.html')]))
    file 'index.html', %(<body><div class="nested"></div></body>\n)

    asset = @env.find('app.css')
    assert_equal "body {\n  color: red;\n}\nbody .nested {\n  margin: 0;\n}", asset.source.rstrip
    assert_nil asset.sourcemap
    assert_nil asset.export.sourcemap
  end

  test 'precompiling writes the map next to the stylesheet and lists it in the manifest' do
    css(sourcemap: :headers)
    @env.register_writer(Condenser::ZlibWriter.new)
    manifest = Condenser::Manifest.new(@env, dir: @dir)
    manifest.compile('app.css')
    export = @env.find('app.css').export

    assert_equal export.sourcemap, File.read(File.join(@dir, "#{export.path}.map"))
    assert_not_includes File.read(File.join(@dir, export.path)), 'sourceMappingURL'
    assert File.exist?(File.join(@dir, "#{export.path}.gz"))
    assert_equal export.sourcemap, Zlib::GzipReader.open(File.join(@dir, "#{export.path}.map.gz"), &:read)

    data = JSON.parse(File.read(manifest.filename))
    assert_equal export.path, data['app.css']['path']
    assert_equal "#{export.path}.map", data['app.css']['sourcemap']

    outputs = export.write(File.join(@dir, 'again'))
    assert_includes outputs, "#{export.path}.map"
    assert_includes outputs, "#{export.path}.map.gz"
  end

  test 'precompiling without a map lists none' do
    css
    manifest = Condenser::Manifest.new(@env, dir: @dir)
    manifest.compile('app.css')

    assert_nil JSON.parse(File.read(manifest.filename))['app.css'].fetch('sourcemap')
    assert_empty Dir.glob(File.join(@dir, '*.map'))
  end

  test 'the server serves the map and links it with a SourceMap header' do
    css(sourcemap: true)
    export = @env.find('app.css').export

    get "/assets/#{export.path}"
    assert_equal 200, last_response.status
    assert_equal 'text/css; charset=utf-8', last_response.headers['Content-Type']
    assert_equal "/assets/#{export.path}.map", last_response.headers['SourceMap']
    assert_includes last_response.body, "/*# sourceMappingURL=#{File.basename(export.path)}.map */"

    get "/assets/#{export.path}.map"
    assert_equal 200, last_response.status
    assert_equal 'application/json', last_response.headers['Content-Type']
    assert_includes last_response.headers['Cache-Control'], 'immutable'
    assert_equal %("#{export.etag}"), last_response.headers['ETag']
    assert_nil last_response.headers['SourceMap']
    assert_equal export.sourcemap, last_response.body

    get "/assets/app.css.map"
    assert_equal 200, last_response.status
    assert_equal export.sourcemap, last_response.body

    head "/assets/#{export.path}.map"
    assert_equal 200, last_response.status
    assert_equal export.sourcemap.bytesize.to_s, last_response.headers['Content-Length']
    assert_empty last_response.body

    get "/assets/app.css.map", {}, 'HTTP_IF_NONE_MATCH' => %("#{export.etag}")
    assert_equal 304, last_response.status

    get "/assets/app-#{'0' * 64}.css.map"
    assert_equal 404, last_response.status
  end

  test 'the server sends the SourceMap header for :headers' do
    css(sourcemap: :headers)
    export = @env.find('app.css').export

    get "/assets/#{export.path}"
    assert_equal 200, last_response.status
    assert_equal "/assets/#{export.path}.map", last_response.headers['SourceMap']
    assert_not_includes last_response.body, 'sourceMappingURL'
  end

  test 'the server sends no SourceMap header for :linked' do
    css(sourcemap: :linked)
    export = @env.find('app.css').export

    get "/assets/#{export.path}"
    assert_equal 200, last_response.status
    assert_nil last_response.headers['SourceMap']
    assert_includes last_response.body, 'sourceMappingURL'

    get "/assets/#{export.path}.map"
    assert_equal 200, last_response.status
    assert_equal export.sourcemap, last_response.body
  end

  test 'the server 404s a map that is not exported' do
    css
    export = @env.find('app.css').export

    get "/assets/#{export.path}"
    assert_nil last_response.headers['SourceMap']

    get "/assets/#{export.path}.map"
    assert_equal 404, last_response.status
  end

  test 'the server 404s the map when the minifier clears it' do
    css(sourcemap: true, minifier: true)
    export = @env.find('app.css').export

    get "/assets/#{export.path}"
    assert_equal 200, last_response.status
    assert_nil last_response.headers['SourceMap']
    assert_not_includes last_response.body, 'sourceMappingURL'

    get "/assets/#{export.path}.map"
    assert_equal 404, last_response.status
  end
end
