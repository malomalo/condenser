require 'test_helper'

class TerserMinifierTest < ActiveSupport::TestCase

  def setup
    super
    @env.unregister_preprocessor('application/javascript', Condenser::BabelProcessor)
    @env.unregister_exporter('application/javascript', Condenser::RollupProcessor)
    @env.register_minifier('application/javascript', Condenser::TerserMinifier)
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
  
end
