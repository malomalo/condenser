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

end
