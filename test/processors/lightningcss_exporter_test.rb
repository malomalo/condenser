require 'test_helper'

class LightningCSSExporterTest < ActiveSupport::TestCase

  def setup
    super
    @env.unregister_minifier('text/css')
  end

  test 'lowers syntax and adds vendor prefixes for the targets' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(targets: { safari: 12, chrome: 80 }))
    file 'main.css', <<~CSS
      .a {
        user-select: none;
        color: lab(50% 40 59);
        .b { color: red; }
      }
    CSS

    assert_exported_file 'main.css', 'text/css', '.a{-webkit-user-select:none;user-select:none;color:#bf5702;color:color(display-p3 .697529 .364974 .135177);color:lab(50% 40 59)}.a .b{color:red}'
  end

  test 'leaves CSS the targets support' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(targets: { chrome: 130 }))
    file 'main.css', <<~CSS
      .a {
        user-select: none;
      }
    CSS

    assert_exported_file 'main.css', 'text/css', '.a{user-select:none}'
  end

  test 'registered as a class minifies without targets' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter)
    file 'main.css', <<~CSS
      .a {
        color: #ff0000;
        margin: 0px 0px 0px 0px;
      }
    CSS

    assert_exported_file 'main.css', 'text/css', '.a{color:red;margin:0}'
  end

  test 'runs on the CSS compiled from SCSS' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(targets: { safari: 12 }))
    file 'main.scss', <<~SCSS
      $select: none;
      .a { user-select: $select; }
    SCSS

    assert_exported_file 'main.css', 'text/css', '.a{-webkit-user-select:none;user-select:none}'
  end

  test 'runs before the minifier' do
    @env.register_minifier('text/css', Condenser::SassMinifier)
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(targets: { safari: 12 }))
    file 'main.css', <<~CSS
      .a {
        user-select: none;
      }
    CSS

    assert_exported_file 'main.css', 'text/css', '.a{-webkit-user-select:none;user-select:none}'
  end

  test 'without minify or targets the CSS is kept as written' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(minify: false))
    file 'main.css', ".a { .b { color: red } }\n"

    assert_exported_file 'main.css', 'text/css', <<~CSS
      .a {
        & .b {
          color: red;
        }
      }
    CSS
  end

  test 'logs warnings with a 1-based line' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(error_recovery: true))
    file 'main.css', <<~CSS
      .a { color: red; }
      .b, { color: blue; }
    CSS

    @env.logger.expects(:warn).with('main.css:2:5: Invalid empty selector')
    @env.find('main.css').export
  end

  test 'raises a syntax error for invalid CSS' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new)
    file 'main.css', <<~CSS
      .a { color: red; }
      .b, { color: blue; }
    CSS

    error = assert_raises(Condenser::SyntaxError) { @env.find('main.css').export }
    assert_equal 'main.css:2:5: Invalid empty selector', error.message
    assert_equal '/assets/main.css:2', error.backtrace[0]
  end

  test 'raises for options condenser sets' do
    assert_raises(ArgumentError) { Condenser::LightningCSSExporter.new(filename: 'x.css') }
    assert_raises(ArgumentError) { Condenser::LightningCSSExporter.new(css_modules: true) }
  end

  test 'raises for targets without minify' do
    error = assert_raises(ArgumentError) { Condenser::LightningCSSExporter.new(targets: { safari: 12 }, minify: false) }
    assert_match(/minify: true/, error.message)
  end

  test 'raises for options Lightning CSS does not know' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(drafts: {}))
    file 'main.css', ".a { color: red; }\n"

    assert_raises(LightningCSS::OptionError) { @env.find('main.css').export }
  end

  test 'the targets and version are part of the export pipeline digest' do
    a = Condenser::LightningCSSExporter.new(targets: { safari: 12, chrome: 80 })
    assert_equal({ 'chrome' => 80, 'safari' => 12 }, a.options[:targets])
    assert_equal LightningCSS::VERSION, a.options[:lightningcss]

    # The order targets are given in doesn't change the digest.
    assert_equal a.options, Condenser::LightningCSSExporter.new(targets: { chrome: 80, safari: 12 }).options

    @env.register_exporter('text/css', a)
    digest = @env.export_pipeline_digest('text/css')
    @env.unregister_exporter('text/css')
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(targets: { safari: 15 }))
    assert_not_equal digest, @env.export_pipeline_digest('text/css')
  end

end
