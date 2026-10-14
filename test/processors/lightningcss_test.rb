require 'test_helper'

class LightningCSSTest < ActiveSupport::TestCase

  def setup
    super
    @env.unregister_minifier('text/css')
  end

  test 'lowers nesting and adds vendor prefixes for the targets' do
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'safari 12'))
    file 'main.css', <<~CSS
      .a {
        user-select: none;
        .b { color: red; }
      }
    CSS

    assert_exported_file 'main.css', 'text/css', <<~CSS
      .a {
        -webkit-user-select: none;
        user-select: none;
      }

      .a .b {
        color: red;
      }
    CSS
  end

  test 'leaves CSS the targets support' do
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'chrome 130'))
    file 'main.css', <<~CSS
      .a {
        user-select: none;
      }
    CSS

    assert_exported_file 'main.css', 'text/css', <<~CSS
      .a {
        user-select: none;
      }
    CSS
  end

  test 'registered as a class uses the default targets' do
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor)
    file 'main.css', <<~CSS
      .a {
        .b { color: red; }
      }
    CSS

    assert_exported_file 'main.css', 'text/css', <<~CSS
      .a .b {
        color: red;
      }
    CSS
  end

  test 'runs on the CSS compiled from SCSS' do
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'safari 12'))
    file 'main.scss', <<~SCSS
      $select: none;
      .a { user-select: $select; }
    SCSS

    assert_exported_file 'main.css', 'text/css', <<~CSS
      .a {
        -webkit-user-select: none;
        user-select: none;
      }
    CSS
  end

  test 'minifies with the minify option' do
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'chrome 130', minify: true))
    file 'main.css', <<~CSS
      .a {
        color: #ff0000;
        margin: 0px 0px 0px 0px;
      }
    CSS

    assert_exported_file 'main.css', 'text/css', '.a{color:red;margin:0}'
  end

  test 'runs before the minifier' do
    @env.register_minifier('text/css', Condenser::SassMinifier)
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'safari 12'))
    file 'main.css', <<~CSS
      .a {
        user-select: none;
      }
    CSS

    assert_exported_file 'main.css', 'text/css', '.a{-webkit-user-select:none;user-select:none}'
  end

  test 'logs warnings' do
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'chrome 130', errorRecovery: true))
    file 'main.css', <<~CSS
      .a { color: red; }
      .b, { color: blue; }
    CSS

    @env.logger.expects(:warn).with { |message| message.start_with?('main.css:2: ') }
    @env.find('main.css').export
  end

  test 'raises a syntax error for invalid CSS' do
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir))
    file 'main.css', <<~CSS
      .a { color: red; }
      .b, { color: blue; }
    CSS

    error = assert_raises(Condenser::SyntaxError) { @env.find('main.css').export }
    assert_equal "/assets/main.css:2", error.backtrace[0]
  end

  test 'raises for an invalid browserslist query' do
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'not a browser 1'))
    file 'main.css', ".a { color: red; }\n"

    error = assert_raises(RuntimeError) { @env.find('main.css').export }
    assert_match(/BrowserslistError/, error.message)
  end

  test 'raises for options condenser sets' do
    assert_raises(ArgumentError) { Condenser::LightningCSSProcessor.new(@npm_dir, filename: 'x.css') }
    assert_raises(ArgumentError) { Condenser::LightningCSSProcessor.new(@npm_dir, sourceMap: true) }
    assert_raises(ArgumentError) { Condenser::LightningCSSProcessor.new(@npm_dir, inputSourceMap: '{}') }
  end

  test 'generates a source map of the exported CSS' do
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'safari 12', sourcemap: true))
    file 'main.css', <<~CSS
      .a {
        user-select: none;
      }
      .b { color: red; }
    CSS

    map = JSON.parse(@env.find('main.css').export.sourcemap)
    assert_equal 3, map['version']
    assert_equal ['main.css'], map['sources']
    assert_equal [File.read(File.join(@path, 'main.css'))], map['sourcesContent']
    # The rules start on lines 1 and 4 of main.css, and lines 1 and 6 of the output
    assert_equal [[0, 0], [5, 3]], mapped_lines(map).map { |out_line, (_, line, _)| [out_line, line] }
  end

  test 'has no source map without the sourcemap option' do
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'safari 12'))
    file 'main.css', ".a { user-select: none; }\n"

    assert_nil @env.find('main.css').export.sourcemap
  end

  test 'chains the incoming source map' do
    exporter = Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'safari 12', sourcemap: true, minify: true)
    [scss_map, JSON.parse(scss_map)].each do |incoming|
      input = { source: scss_output, filename: 'app.css', map: incoming }
      exporter.call(@env, input)

      map = JSON.parse(input[:map])
      scss = map['sources'].index('app.scss')
      assert scss, "app.scss isn't in the sources: #{map['sources'].inspect}"
      assert_equal map['sourcesContent'][scss], scss_source
      # Every mapping points into app.scss, at the lines the rules came from
      assert_equal [[scss, 1], [scss, 2]], mapped_lines(map).map { |_, (source, line, _)| [source, line] }
    end
  end

  test 'drops the incoming source map without the sourcemap option' do
    exporter = Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'safari 12')
    input = { source: scss_output, filename: 'app.css', map: scss_map }
    exporter.call(@env, input)

    assert_nil input[:map]
  end

  test 'raises for an incoming source map that is not JSON' do
    exporter = Condenser::LightningCSSProcessor.new(@npm_dir, sourcemap: true)
    error = assert_raises(ArgumentError) { exporter.call(@env, { source: scss_output, filename: 'app.css', map: 'not json' }) }
    assert_match(/app\.css: source map isn't valid JSON/, error.message)
  end

  test 'the Sass minifier drops the source map' do
    @env.register_minifier('text/css', Condenser::SassMinifier)
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'safari 12', sourcemap: true))
    file 'main.css', ".a { user-select: none; }\n"

    export = @env.find('main.css').export
    assert_equal '.a{-webkit-user-select:none;user-select:none}', export.source.rstrip
    assert_nil export.sourcemap
  end

  test 'sourcemap is part of the export pipeline digest' do
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir))
    digest = @env.export_pipeline_digest('text/css')
    @env.unregister_exporter('text/css')
    @env.register_exporter('text/css', Condenser::LightningCSSProcessor.new(@npm_dir, sourcemap: true))
    assert_not_equal digest, @env.export_pipeline_digest('text/css')
  end

  test 'the targets and package versions are part of the export pipeline digest' do
    a = Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'safari 12')
    b = Condenser::LightningCSSProcessor.new(@npm_dir, targets: 'chrome 130')
    assert_equal 'safari 12', a.options[:targets]
    assert a.options['lightningcss']
    assert a.options['caniuse-lite']

    @env.register_exporter('text/css', a)
    digest = @env.export_pipeline_digest('text/css')
    @env.unregister_exporter('text/css')
    @env.register_exporter('text/css', b)
    assert_not_equal digest, @env.export_pipeline_digest('text/css')
  end

  private

  # CSS as Sass outputs app.scss below, with a source map back to it.
  def scss_source
    "$c: red;\n.a { user-select: none; }\n.b { color: $c; }\n"
  end

  def scss_output
    ".a {\n  user-select: none;\n}\n\n.b {\n  color: red;\n}\n"
  end

  def scss_map
    JSON.generate(version: 3, sources: ['app.scss'], sourcesContent: [scss_source], names: [], mappings: 'AACA;EAAI;;;AACJ;EAAI', file: 'app.css')
  end

  BASE64 = ('A'..'Z').to_a + ('a'..'z').to_a + ('0'..'9').to_a + %w(+ /)

  # The segments of a source map as [output line, [source, line, column]]
  # (all 0-based), skipping segments without a source.
  def mapped_lines(map)
    source = line = column = 0
    map['mappings'].split(';', -1).each_with_index.flat_map do |segments, out_line|
      out_column = 0
      segments.split(',').filter_map do |segment|
        values = vlq_decode(segment)
        out_column += values[0]
        next if values.size < 4
        source += values[1]
        line += values[2]
        column += values[3]
        [out_line, [source, line, column]]
      end
    end
  end

  def vlq_decode(segment)
    values = []
    value = shift = 0
    segment.each_char do |char|
      digit = BASE64.index(char)
      value += (digit & 31) << shift
      if digit & 32 == 0
        values << ((value & 1) == 1 ? -(value >> 1) : value >> 1)
        value = shift = 0
      else
        shift += 5
      end
    end
    values
  end

end
