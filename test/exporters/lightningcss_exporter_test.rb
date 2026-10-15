require 'test_helper'
require 'lightningcss'

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

    assert_exported_file 'main.css', 'text/css', <<~CSS
      .a {
        -webkit-user-select: none;
        user-select: none;
        color: #bf5702;
        color: color(display-p3 .697529 .364974 .135177);
        color: lab(50% 40 59);
      }

      .a .b {
        color: red;
      }
    CSS
  end

  test 'leaves CSS the targets support' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(targets: { chrome: 130 }))
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

  test 'targets can include the minor version' do
    file 'main.css', ".a { color: oklch(60% .2 30); }\n"

    export = lambda do |version|
      env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path)
      env.unregister_minifier('text/css')
      env.register_exporter('text/css', Condenser::LightningCSSExporter.new(targets: { safari: version }))
      env.find('main.css').export.source
    end

    assert_equal ".a {\n  color: lab(51.6908% 61.9679 48.0969);\n}\n", export.call(15)
    assert_equal ".a {\n  color: oklch(60% .2 30);\n}\n", export.call(15.4)
    assert_equal ".a {\n  color: oklch(60% .2 30);\n}\n", export.call('15.4')
  end

  test 'without targets keeps the CSS as written' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new)
    file 'main.css', ".a { .b { color: red } }\n"

    assert_exported_file 'main.css', 'text/css', <<~CSS
      .a {
        & .b {
          color: red;
        }
      }
    CSS
  end

  test 'runs on the CSS compiled from SCSS' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(targets: { safari: 12 }))
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

  test 'minifies with the minify option' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(targets: { safari: 12 }, minify: true))
    file 'main.css', <<~CSS
      .a {
        user-select: none;
        margin: 0px 0px 0px 0px;
      }
    CSS

    assert_exported_file 'main.css', 'text/css', '.a{-webkit-user-select:none;user-select:none;margin:0}'
  end

  test 'logs warnings with their location' do
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

  test 'raises when the lightningcss gem is missing' do
    with_lightningcss_constant(:Backend, nil) do
      Condenser::LightningCSSExporter.stubs(:require).with('lightningcss').raises(LoadError)

      error = assert_raises(LoadError) { Condenser::LightningCSSExporter.new }
      assert_equal "Condenser::LightningCSSExporter requires the lightningcss gem, add `gem 'lightningcss', '>= 1.33.0.2'` to your Gemfile", error.message
    end
  end

  test 'raises when the lightningcss gem is too old' do
    with_lightningcss_constant(:VERSION, '1.33.0.1') do
      error = assert_raises(LoadError) { Condenser::LightningCSSExporter.new }
      assert_equal 'Condenser::LightningCSSExporter requires lightningcss 1.33.0.2 or later, 1.33.0.1 is installed', error.message
    end
  end

  test 'raises for options condenser sets' do
    assert_raises(ArgumentError) { Condenser::LightningCSSExporter.new(filename: 'x.css') }
    assert_raises(ArgumentError) { Condenser::LightningCSSExporter.new(css_modules: true) }
  end

  test 'raises for an invalid target version' do
    @env.register_exporter('text/css', Condenser::LightningCSSExporter.new(targets: { safari: 'abc' }))
    file 'main.css', ".a { color: red; }\n"

    assert_raises(LightningCSS::OptionError) { @env.find('main.css').export }
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

  private

  # Replaces LightningCSS::<name> with +value+ (or removes it if nil) for
  # the block.
  def with_lightningcss_constant(name, value)
    original = LightningCSS.const_get(name)
    LightningCSS.send(:remove_const, name)
    LightningCSS.const_set(name, value) unless value.nil?
    yield
  ensure
    LightningCSS.send(:remove_const, name) if LightningCSS.const_defined?(name, false)
    LightningCSS.const_set(name, original)
  end

end
