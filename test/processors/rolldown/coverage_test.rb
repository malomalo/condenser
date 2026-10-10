require 'test_helper'

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

end
