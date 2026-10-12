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

end
