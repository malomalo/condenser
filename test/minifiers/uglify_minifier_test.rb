require 'test_helper'

class UglifyMinifierTest < ActiveSupport::TestCase

  def setup
    super
    @env.unregister_preprocessor('application/javascript', Condenser::BabelProcessor)
    @env.unregister_exporter('application/javascript', Condenser::RollupProcessor)
  end

  test 'simple example' do
    file 'test.js', <<~JS
      function fa() {
        var u;
        var al = 1;
        var bl = 2;
        console.log(al);

        return 2 + 3;
      }
    JS
    
    @env.logger.expects(:warn).with('WARN: Dropping unused variable a [test.js:2,6]')
    @env.logger.expects(:warn).with('WARN: Dropping unused variable c [test.js:4,6]')
    
    assert_exported_file 'test.js', 'application/javascript', <<~CSS
      function fa(){return console.log(1),5}
    CSS
  end
  
end
