require 'test_helper'
require 'lightningcss'

class LightningCSSMinifierTest < ActiveSupport::TestCase

  test 'is the default text/css minifier' do
    assert_instance_of Condenser::LightningCSSMinifier, @env.minifier_for('text/css')
  end

  test 'minifies' do
    file 'test.css', <<~CSS
      /* a comment */
      * {
        background: #FFFFFF;
        margin: 0px 0px 0px 0px;
      }
    CSS

    assert_exported_file 'test.css', 'text/css', '*{background:#fff;margin:0}'
  end

  test 'minifies compiled scss' do
    file 'test.scss', <<~SCSS
      $color: rgba(255, 0, 0, 1);
      @media (min-width: 100px) {
        .a, .b {
          color: $color;
          &:hover { color: blue; }
        }
      }
    SCSS

    assert_exported_file 'test.css', 'text/css', '@media (width>=100px){.a,.b{color:red}.a:hover,.b:hover{color:#00f}}'
  end

  test 'lowers syntax for the targets' do
    @env.register_minifier('text/css', Condenser::LightningCSSMinifier.new(targets: { safari: 12 }))
    file 'test.css', <<~CSS
      .a {
        user-select: none;
        .b { color: red; }
      }
    CSS

    assert_exported_file 'test.css', 'text/css', '.a{-webkit-user-select:none;user-select:none}.a .b{color:red}'
  end

  test 'without targets keeps the CSS syntax as written' do
    file 'test.css', ".a { .b { color: red } }\n"

    assert_exported_file 'test.css', 'text/css', '.a{& .b{color:red}}'
  end

  test 'raises for options condenser sets' do
    %i(filename css_modules minify).each do |key|
      error = assert_raises(ArgumentError) { Condenser::LightningCSSMinifier.new(key => true) }
      assert_match "LightningCSSMinifier options can't include :#{key}, ", error.message
    end
  end

  test 'always minifies, without the exporter\'s default options' do
    minifier = Condenser::LightningCSSMinifier.new(targets: { safari: 12, chrome: 80 }, error_recovery: true)

    assert_equal 'Condenser::LightningCSSMinifier', minifier.name
    assert_equal({ error_recovery: true, targets: { 'chrome' => 80, 'safari' => 12 }, minify: true, lightningcss: LightningCSS::VERSION }, minifier.options)
    assert_equal [:error_recovery, :targets, :minify, :lightningcss], minifier.options.keys
  end

  test 'names the minifier when the lightningcss gem is missing' do
    backend = LightningCSS::Backend
    Condenser::LightningCSSMinifier.stubs(:require).with('lightningcss').raises(LoadError)
    LightningCSS.send(:remove_const, :Backend)

    minifier = Condenser::LightningCSSMinifier.new
    error = assert_raises(LoadError) { minifier.setup(@env) }
    assert_equal "Condenser::LightningCSSMinifier requires the lightningcss gem, add `gem 'lightningcss', '>= 1.33.0.2'` to your Gemfile", error.message
  ensure
    LightningCSS.const_set(:Backend, backend)
  end

  test 'raises a syntax error with the location for invalid CSS' do
    file 'test.css', <<~CSS
      .a { color: red; }
      .b, { color: blue; }
    CSS

    error = assert_raises(Condenser::SyntaxError) { @env.find('test.css').export }
    assert_equal 'test.css:2:5: Invalid empty selector', error.message
    assert_equal '/assets/test.css:2', error.backtrace[0]
  end

  test 'logs warnings with their location' do
    @env.register_minifier('text/css', Condenser::LightningCSSMinifier.new(error_recovery: true))
    file 'test.css', <<~CSS
      .a { color: red; }
      .b, { color: blue; }
    CSS

    @env.logger.expects(:warn).with('test.css:2:5: Invalid empty selector')
    assert_exported_file 'test.css', 'text/css', '.a{color:red}'
  end

  test 'the targets and version are part of the export pipeline digest' do
    a = Condenser::LightningCSSMinifier.new(targets: { safari: 12, chrome: 80 })
    assert_equal({ minify: true, targets: { 'chrome' => 80, 'safari' => 12 }, lightningcss: LightningCSS::VERSION }, a.options)
    assert_equal({ minify: true, lightningcss: LightningCSS::VERSION }, Condenser::LightningCSSMinifier.new.options)

    digest = @env.export_pipeline_digest('text/css')
    @env.register_minifier('text/css', a)
    assert_not_equal digest, @env.export_pipeline_digest('text/css')
  end

  test 'the default pipeline loads without the lightningcss gem and raises when CSS is minified' do
    Condenser::LightningCSSMinifier.stubs(:require_lightningcss!).raises(LoadError, "Condenser::LightningCSSMinifier requires the lightningcss gem")

    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path)
    assert_instance_of Condenser::LightningCSSMinifier, env.minifier_for('text/css')

    file 'test.css', ".a { color: red; }\n"
    error = assert_raises(LoadError) { env.find('test.css').export }
    assert_equal "Condenser::LightningCSSMinifier requires the lightningcss gem", error.message
  end

end
