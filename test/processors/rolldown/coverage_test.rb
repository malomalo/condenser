require 'test_helper'
require 'open3'

class RolldownCoverageTest < ActiveSupport::TestCase

  def setup
    super
    @env.unregister_minifier('application/javascript')
    register_rolldown
  end

  def register_rolldown(**options)
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path, **options))
  end

  def run_bundle(name)
    File.write(File.join(@path, 'bundle.mjs'), @env.find(name).export.source)
    stdout, stderr, status = Open3.capture3('node', File.join(@path, 'bundle.mjs'))
    assert status.success?, stderr
    stdout
  end

  [:keep, :local].each do |mode|
    test "dynamic_imports: #{mode.inspect} rewrites dynamic imports as URLs" do
      register_rolldown(dynamic_imports: mode, prefix: '/assets')

      file 'main.js', <<~JS
        const math = await import('./math/math');
        const remote = await import('https://example.com/remote.js');

        console.log( math.cube( 5 ), remote );
      JS
      file 'math/math.js', <<~JS
        export function cube ( x ) {
          return x * x * x;
        }
      JS

      source = @env.find('main.js').export.source
      assert_includes source, %{import("/assets/#{@env.find('math/math.js').path}")}
      assert_includes source, 'import("https://example.com/remote.js")'
      assert_not_includes source, 'x * x * x'
      assert_equal mode, @env.exporters['application/javascript'].first.options[:dynamic_imports]
    end
  end

  test 'an unresolved relative import raises an error naming the import' do
    file 'main.js', <<~JS
      import x from './missing.js';

      console.log( x );
    JS

    error = assert_raises(RuntimeError) { @env.find('main.js').export }
    assert error.message.start_with?("Error: #{@path}/main.js:1:15: [UNRESOLVED_IMPORT] Could not resolve './missing.js' in main.js"), error.message
    assert_not_includes error.message, "\e["
  end

  test 'a syntax error in an npm module raises an error naming the file' do
    package = File.join(@npm_dir, 'node_modules', 'condenser-rolldown-syntax-error-test')
    FileUtils.mkdir_p(package)
    File.write(File.join(package, 'package.json'), JSON.generate({ name: 'condenser-rolldown-syntax-error-test', module: './index.js' }))
    File.write(File.join(package, 'index.js'), "export default function ( {\n")
    file 'main.js', <<~JS
      import broken from 'condenser-rolldown-syntax-error-test';

      console.log( broken );
    JS

    error = assert_raises(RuntimeError) { @env.find('main.js').export }
    assert error.message.start_with?("Error: #{File.realpath(File.join(package, 'index.js'))}:"), error.message
    assert_includes error.message, '[PARSE_ERROR]'
    assert_not_includes error.message, "\e["
  ensure
    FileUtils.rm_rf(package)
  end

  test 'import glob via /**/* includes nested directories' do
    file 'main.js', <<~JS
      import 'initializers/**/*';

      console.log( [a, b, c].join(' ') );
    JS
    file 'initializers/a.js', "globalThis.a = 'top';\n"
    file 'initializers/sub/b.js', "globalThis.b = 'nested';\n"
    file 'initializers/sub/deep/c.js', "globalThis.c = 'deeper';\n"

    assert_equal "top nested deeper\n", run_bundle('main.js')
  end

  test 'import glob via /**/* as array' do
    file 'main.js', <<~JS
      import initializers from 'initializers/**/*';

      initializers.forEach((initializer) => initializer());
    JS
    file 'initializers/a.js', "export default function a () { console.log('top'); }\n"
    file 'initializers/sub/b.js', "export default function b () { console.log('nested'); }\n"

    assert_equal "top\nnested\n", run_bundle('main.js')
  end

  test 'import an svg file' do
    file 'icon.svg', <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0L10 10"/></svg>
    SVG
    file 'main.js', <<~JS
      import icon from './icon.svg';

      document.body.append( icon() );
    JS

    source = @env.find('main.js').export.source
    assert_includes source, 'document.createElementNS("http://www.w3.org/2000/svg", "svg")'
    assert_includes source, '"0 0 10 10"'
    assert_includes source, '"M0 0L10 10"'
    assert_not_includes source, '<svg'
  end

  test 'import a jst file' do
    file 'template.jst', <<~JS
      export default function (locals) {
          return "<b>" + name + "</b>";
      }
    JS
    file 'main.js', <<~JS
      import template from './template';

      console.log( template({ name: 'x' }) );
    JS

    assert_equal "<b>x</b>\n", run_bundle('main.js')
  end

  test 'bundler_path: builds with the Rolldown at that path' do
    rolldown = File.realpath(File.join(@npm_dir, 'node_modules', 'rolldown'))
    file 'wrapped-rolldown/package.json', JSON.generate({ name: 'rolldown', version: '0.0.1-wrapped', main: './index.js' })
    file 'wrapped-rolldown/index.js', <<~JS
      const real = require(#{JSON.generate(rolldown)});
      module.exports = {
        ...real,
        rolldown(options) {
          options.transform.define.__BUNDLER__ = JSON.stringify('wrapped');
          return real.rolldown(options);
        }
      };
    JS
    file 'main.js', <<~JS
      console.log( typeof __BUNDLER__ === 'undefined' ? 'npm' : __BUNDLER__ );
    JS

    register_rolldown(bundler_path: File.join(@path, 'wrapped-rolldown'))
    assert_equal '0.0.1-wrapped', @env.exporters['application/javascript'].first.options[:rolldown]
    assert_equal "wrapped\n", run_bundle('main.js')
  end

end
