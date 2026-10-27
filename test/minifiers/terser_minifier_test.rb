require 'test_helper'

class TerserMinifierTest < ActiveSupport::TestCase

  def setup
    super
    @env.unregister_exporter('application/javascript')
    @env.register_minifier('application/javascript', Condenser::TerserMinifier.new(@npm_dir))
  end

  test 'simple example' do
    file 'test.js', <<~JS
      class MyClass {
        fn() {
          console.log( "Hello" );
        }
      }
      
      function fa() {
        var u;
        var al = 1;
        var bl = 2;
        console.log(al);

        return 2 + 3;
      }
    JS
    
    # @env.logger.expects(:warn).with('Dropping unused variable u [test.js:8,6]')
    # @env.logger.expects(:warn).with('Dropping unused variable bl [test.js:10,6]')
    
    assert_exported_file 'test.js', 'application/javascript', <<~CSS
      class MyClass{fn(){console.log("Hello")}}function fa(){return console.log(1),5}
    CSS
  end

  test 'can be registered as an instance, with its options in the export pipeline digest' do
    minifier = Condenser::TerserMinifier.new(@npm_dir, mangle: false)
    assert_equal({ mangle: false, keep_classnames: true, keep_fnames: true }, minifier.options)

    digest = @env.export_pipeline_digest('application/javascript')
    @env.register_minifier('application/javascript', minifier)
    assert_not_equal digest, @env.export_pipeline_digest('application/javascript')

    file 'test.js', "function fa(value) { console.log(value); }\n"
    assert_exported_file 'test.js', 'application/javascript', 'function fa(value){console.log(value)}'
  end

end
