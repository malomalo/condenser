require 'test_helper'

class RollupTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.unregister_preprocessor('application/javascript', Condenser::BabelProcessor)
  end
  
  test 'import file' do
    file 'main.js', <<~JS
      import { cube } from './math.js';

      console.log( cube( 5 ) ); // 125
    JS
    file 'math.js', <<~JS
    
      // This function isn't used anywhere, so
      // Rollup excludes it from the bundle...
      export function square ( x ) {
        return x * x;
      }

      // This function gets included
      export function cube ( x ) {
        return x * x * x;
      }
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      (function () {
      'use strict';

      // This function gets included
      function cube ( x ) {
        return x * x * x;
      }

      console.log( cube( 5 ) ); // 125

      }());
    FILE
  end
  
  test 'import an erb file' do
    file 'main.js', <<~JS
      import { cube } from './math.js';

      console.log( cube( 5 ) ); // 125
    JS
    file 'math.js.erb', <<~JS
      export function cube ( x ) {
        return <%= 2 %> * x * x;
      }
    JS
    
    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      (function () {
      'use strict';

      function cube ( x ) {
        return 2 * x * x;
      }

      console.log( cube( 5 ) ); // 125

      }());
    FILE
  end
  
end
