require 'test_helper'
require 'rack/builder'
require 'rack/test'
require 'rack/lint'

class SourcemapTest < ActiveSupport::TestCase
  include Rack::Test::Methods

  BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

  # Rewrites the bundle without updating the map, so it clears it.
  class RewritingMinifier < Condenser::Processor
    def call(environment, input)
      input[:source] = "/* minified */\n" + input[:source]
      input[:sourcemap] = nil
    end
  end

  # Leaves the bundle and its map as they are.
  class NoopMinifier < Condenser::Processor
    def call(environment, input)
    end
  end

  def setup
    super
    @dir = Dir.mktmpdir
    @packages = []
    file 'main.js', <<~JS
      import { cube } from './lib/math.js';

      // A comment, so the source lines differ from the bundle's.
      console.log( cube( 5 ) );
    JS
    file 'lib/math.js', <<~JS
      export function square ( x ) {
        return x * x;
      }

      export function cube ( number ) {
        return number * number * number;
      }
    JS
  end

  def teardown
    @packages.each { |package| FileUtils.rm_rf(package) }
    FileUtils.remove_entry(@dir, true)
    super
  end

  def rolldown(**options)
    @env.unregister_minifier('application/javascript')
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path, **options))
  end

  def app
    server = Condenser::Server.new(@env)
    Rack::Lint.new(Rack::Builder.new { map("/assets") { run server } })
  end

  # Decodes the "mappings" into lines of [column, source, line, column]
  # segments, all 0-based.
  def decode_mappings(mappings)
    source = line = column = 0
    mappings.split(';', -1).map do |generated|
      generated_column = 0
      generated.split(',').map do |segment|
        values = []
        value = shift = 0
        segment.each_char do |char|
          digit = BASE64.index(char)
          value += (digit & 31) << shift
          if digit & 32 == 0
            values << (value.odd? ? -(value >> 1) : value >> 1)
            value = shift = 0
          else
            shift += 5
          end
        end
        generated_column += values[0]
        next [generated_column] if values.size < 4
        source += values[1]
        line += values[2]
        column += values[3]
        [generated_column, source, line, column]
      end
    end
  end

  # The [source, line, column] (0-based) that +needle+ in +code+ maps back to.
  def original_position(code, map, needle)
    index = code.index(needle)
    assert index, "#{needle.inspect} isn't in the bundle"
    line = code[0...index].count("\n")
    column = index - (code.rindex("\n", index - 1)&.+(1) || 0)
    segment = decode_mappings(map['mappings'])[line].select { |s| s[0] <= column }.last
    assert segment && segment.size >= 4, "#{needle.inspect} isn't mapped"
    [map['sources'][segment[1]], segment[2], segment[3]]
  end

  test 'sourcemap is false by default' do
    assert_equal false, @env.sourcemap
    assert_equal false, Condenser.new(@path, listen: false, pipeline: false).sourcemap
  end

  test 'sourcemap must be false, true, :linked or :headers' do
    error = assert_raises(ArgumentError) { Condenser.new(@path, listen: false, sourcemap: :hidden) }
    assert_equal 'sourcemap must be false, true, :linked or :headers, got :hidden', error.message

    error = assert_raises(ArgumentError) { @env.sourcemap = nil }
    assert_equal 'sourcemap must be false, true, :linked or :headers, got nil', error.message
    assert_equal false, @env.sourcemap

    [true, :linked, :headers, false].each do |value|
      @env.sourcemap = value
      assert_equal value, @env.sourcemap
    end
  end

  test 'RolldownProcessor has no sourcemap option' do
    error = assert_raises(ArgumentError) { Condenser::RolldownProcessor.new(@env.npm_path, sourcemap: :linked) }
    assert_equal 'unknown keyword: :sourcemap', error.message
  end

  test 'sourcemap is in the export pipeline digest' do
    rolldown
    digests = [false, true, :linked, :headers].map do |value|
      @env.sourcemap = value
      @env.export_pipeline_digest('application/javascript')
    end
    assert_equal 4, digests.uniq.size
  end

  test 'the etag and output change between values' do
    exports = [false, true, :linked, :headers].to_h do |value|
      env = Condenser.new(@path, logger: @env.logger, npm_path: @npm_dir, base: @path, listen: false, sourcemap: value)
      [value, env.find('main.js').export]
    end

    assert_equal @env.find('main.js').export.etag, exports[false].etag
    assert_equal 4, exports.values.map(&:etag).uniq.size
    assert_includes exports[:linked].source, 'sourceMappingURL'
    assert_not_includes exports[:headers].source, 'sourceMappingURL'
    assert_equal exports[:headers].source, exports[false].source
  end

  test 'sourcemap: false exports no map and no comment' do
    rolldown
    export = assert_exported_file 'main.js', 'application/javascript', <<~JS
      // lib/math.js
      function cube(number) {
      	return number * number * number;
      }
      // main.js
      console.log(cube(5));
    JS
    assert_nil export.sourcemap
    assert_nil export.sourcemap_path
    assert_nil export.to_json.fetch(:sourcemap)
  end

  test 'sourcemap: true exports a map and links it from the bundle' do
    rolldown
    @env.sourcemap = true
    export = @env.find('main.js').export
    map = JSON.parse(export.sourcemap)

    assert_equal 3, map['version']
    assert_equal ['lib/math.js', 'main.js'], map['sources']
    assert_equal File.read(File.join(@path, 'lib/math.js')), map['sourcesContent'][0]
    assert_equal File.read(File.join(@path, 'main.js')), map['sourcesContent'][1]

    assert_equal "#{export.path}.map", export.sourcemap_path
    assert export.source.end_with?("console.log(cube(5));\n//# sourceMappingURL=#{File.basename(export.path)}.map\n")
    assert_equal @env.digestor.digest(export.source), export.digest
  end

  test 'sourcemap: :linked exports a map with the comment' do
    rolldown
    @env.sourcemap = :linked
    export = @env.find('main.js').export

    assert_equal ['lib/math.js', 'main.js'], JSON.parse(export.sourcemap)['sources']
    assert export.source.end_with?("console.log(cube(5));\n//# sourceMappingURL=#{File.basename(export.path)}.map\n")
  end

  test 'sourcemap: :headers exports a map without the comment' do
    rolldown
    @env.sourcemap = :headers
    export = @env.find('main.js').export

    assert_equal ['lib/math.js', 'main.js'], JSON.parse(export.sourcemap)['sources']
    assert_equal "#{export.path}.map", export.sourcemap_path
    assert_not_includes export.source, 'sourceMappingURL'
  end

  test 'Condenser.new(sourcemap:) sets it' do
    env = Condenser.new(@path, logger: @env.logger, npm_path: @npm_dir, base: @path, listen: false, sourcemap: :linked)
    export = env.find('main.js').export

    assert_equal :linked, env.sourcemap
    assert_equal ['lib/math.js', 'main.js'], JSON.parse(export.sourcemap)['sources']
    assert export.source.end_with?("\n//# sourceMappingURL=#{File.basename(export.path)}.map\n")
  end

  test 'the mappings point back to the sources' do
    rolldown
    @env.sourcemap = true
    export = @env.find('main.js').export
    map = JSON.parse(export.sourcemap)

    assert_equal ['lib/math.js', 5, 2], original_position(export.source, map, 'return number')
    assert_equal ['main.js', 3, 0], original_position(export.source, map, 'console.log')
    assert_equal ['main.js', 3, 13], original_position(export.source, map, 'cube(5)')
  end

  test 'the mappings point back to the sources with minify: true' do
    rolldown(minify: true)
    @env.sourcemap = true
    export = @env.find('main.js').export
    map = JSON.parse(export.sourcemap)

    assert export.source.start_with?("function e(e){return e*e*e}console.log(e(5));\n//# sourceMappingURL=")
    assert_equal ['lib/math.js', 5, 2], original_position(export.source, map, 'return')
    assert_equal ['main.js', 3, 0], original_position(export.source, map, 'console.log')
    assert_includes map['names'], 'cube'
  end

  test 'npm sources are relative to the npm path' do
    package = File.join(@npm_dir, 'node_modules', 'condenser-rolldown-sourcemap-test')
    @packages << package
    FileUtils.mkdir_p(package)
    File.write(File.join(package, 'package.json'), JSON.generate(name: 'condenser-rolldown-sourcemap-test', module: './index.js'))
    File.write(File.join(package, 'index.js'), "export default function hello() { return 'hello'; }\n")
    file 'npm.js', <<~JS
      import hello from 'condenser-rolldown-sourcemap-test';
      console.log( hello() );
    JS

    rolldown
    @env.sourcemap = :headers
    map = JSON.parse(@env.find('npm.js').export.sourcemap)
    assert_equal ['node_modules/condenser-rolldown-sourcemap-test/index.js', 'npm.js'], map['sources']
  end

  test 'a minifier that clears the map exports none' do
    rolldown
    @env.sourcemap = true
    @env.register_minifier('application/javascript', RewritingMinifier.new)
    export = @env.find('main.js').export

    assert export.source.start_with?("/* minified */\n")
    assert_nil export.sourcemap
    assert_not_includes export.source, 'sourceMappingURL'
  end

  test 'a minifier that leaves the map keeps it' do
    rolldown
    @env.sourcemap = true
    @env.register_minifier('application/javascript', NoopMinifier.new)
    export = @env.find('main.js').export

    assert_equal ['lib/math.js', 'main.js'], JSON.parse(export.sourcemap)['sources']
    assert export.source.end_with?("\n//# sourceMappingURL=#{File.basename(export.path)}.map\n")
  end

  test 'TerserMinifier maps the minified bundle back to the sources' do
    rolldown
    @env.sourcemap = true
    @env.register_minifier('application/javascript', Condenser::TerserMinifier.new(@npm_dir))
    export = @env.find('main.js').export
    map = JSON.parse(export.sourcemap)

    assert_equal "function cube(c){return c*c*c}console.log(cube(5));\n//# sourceMappingURL=#{File.basename(export.path)}.map\n", export.source
    assert_equal 1, export.source.scan('sourceMappingURL').size
    assert_equal ['lib/math.js', 'main.js'], map['sources']
    assert_equal File.read(File.join(@path, 'lib/math.js')), map['sourcesContent'][0]
    assert_equal File.read(File.join(@path, 'main.js')), map['sourcesContent'][1]
    assert_equal ['lib/math.js', 5, 2], original_position(export.source, map, 'return')
    assert_equal ['main.js', 3, 0], original_position(export.source, map, 'console.log')
  end

  test 'TerserMinifier with sourcemap: :headers exports the map without the comment' do
    rolldown
    @env.sourcemap = :headers
    @env.register_minifier('application/javascript', Condenser::TerserMinifier.new(@npm_dir))
    export = @env.find('main.js').export
    map = JSON.parse(export.sourcemap)

    assert_equal 'function cube(c){return c*c*c}console.log(cube(5));', export.source
    assert_equal ['lib/math.js', 'main.js'], map['sources']
    assert_equal ['lib/math.js', 5, 2], original_position(export.source, map, 'return')
  end

  test 'TerserMinifier without sourcemap exports no map' do
    rolldown
    @env.register_minifier('application/javascript', Condenser::TerserMinifier.new(@npm_dir))
    export = @env.find('main.js').export

    assert_equal 'function cube(c){return c*c*c}console.log(cube(5));', export.source
    assert_nil export.sourcemap
  end

  test 'precompiling writes the map next to the bundle and lists it in the manifest' do
    rolldown
    @env.sourcemap = :headers
    @env.register_writer(Condenser::ZlibWriter.new)
    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))
    manifest.compile('main.js')
    export = @env.find('main.js').export

    assert_equal export.sourcemap, File.read(File.join(@dir, "#{export.path}.map"))
    assert_not_includes File.read(File.join(@dir, export.path)), 'sourceMappingURL'
    assert File.exist?(File.join(@dir, "#{export.path}.gz"))
    assert_equal export.sourcemap, Zlib::GzipReader.open(File.join(@dir, "#{export.path}.map.gz"), &:read)

    data = JSON.parse(File.read(manifest.filename))
    assert_equal export.path, data['main.js']['path']
    assert_equal "#{export.path}.map", data['main.js']['sourcemap']

    outputs = export.write(File.join(@dir, 'again'))
    assert_includes outputs, 'main.js.map'
    assert_includes outputs, 'main.js.map.gz'
  end

  test 'precompiling without a map lists none' do
    rolldown
    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))
    manifest.compile('main.js')

    assert_nil JSON.parse(File.read(manifest.filename))['main.js'].fetch('sourcemap')
    assert_empty Dir.glob(File.join(@dir, '*.map'))
  end

  test 'the server serves the map and links it with a SourceMap header' do
    rolldown
    @env.sourcemap = true
    export = @env.find('main.js').export

    get "/assets/#{export.path}"
    assert_equal 200, last_response.status
    assert_equal "/assets/#{export.path}.map", last_response.headers['SourceMap']

    get "/assets/#{export.path}.map"
    assert_equal 200, last_response.status
    assert_equal 'application/json', last_response.headers['Content-Type']
    assert_includes last_response.headers['Cache-Control'], 'immutable'
    assert_equal export.sourcemap, last_response.body

    get "/assets/main.js.map"
    assert_equal 200, last_response.status
    assert_equal export.sourcemap, last_response.body

    head "/assets/#{export.path}.map"
    assert_equal 200, last_response.status
    assert_equal export.sourcemap.bytesize.to_s, last_response.headers['Content-Length']

    get "/assets/main-#{'0' * 64}.js.map"
    assert_equal 404, last_response.status
  end

  test 'the server sends the SourceMap header for :headers' do
    rolldown
    @env.sourcemap = :headers
    export = @env.find('main.js').export

    get "/assets/#{export.path}"
    assert_equal 200, last_response.status
    assert_equal "/assets/#{export.path}.map", last_response.headers['SourceMap']
    assert_not_includes last_response.body, 'sourceMappingURL'
  end

  test 'the server sends no SourceMap header for :linked' do
    rolldown
    @env.sourcemap = :linked
    export = @env.find('main.js').export

    get "/assets/#{export.path}"
    assert_equal 200, last_response.status
    assert_nil last_response.headers['SourceMap']
    assert_includes last_response.body, 'sourceMappingURL'

    get "/assets/#{export.path}.map"
    assert_equal 200, last_response.status
    assert_equal export.sourcemap, last_response.body
  end

  test 'the server 404s a map that is not exported' do
    rolldown
    export = @env.find('main.js').export

    get "/assets/#{export.path}"
    assert_nil last_response.headers['SourceMap']

    get "/assets/#{export.path}.map"
    assert_equal 404, last_response.status
  end
end
