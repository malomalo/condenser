require 'test_helper'

class RollupTest < ActiveSupport::TestCase
  
  def setup
    super
    # @env.unregister_preprocessor('application/javascript')
    @env.unregister_minifier('application/javascript')
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

        // This function isn't used anywhere, so

        function cube(x) {
          return x * x * x;
        }

        console.log(cube(5)); // 125

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

        function cube(x) {
          return 2 * x * x;
        }

        console.log(cube(5)); // 125

      }());
    FILE
  end

  test 'import a file with the same name as another css file' do
    file 'a/main.js', <<~JS
      import { cube } from 'math';

      console.log( cube( 5 ) ); // 125
    JS
    file 'a/math.css', <<~CSS
      * {
        background: green;
      }
    CSS
    file 'b/math.js', <<~JS
      export function cube ( x ) {
        return x * x * x;
      }
    JS

    @env.append_path File.join(@path, 'b')
    @env.append_path File.join(@path, 'a')

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      (function () {
        'use strict';

        function cube(x) {
          return x * x * x;
        }

        console.log(cube(5)); // 125

      }());
    FILE
  end

  test 'import glob via /*' do
    file 'main.js', <<~JS
      import 'maths/*';

      console.log( square(cube( 5 )) );
    JS
    
    file 'maths/square.js', <<~JS
      window.square = function ( x ) {
        return x * x;
      };
    JS
    
    file 'maths/cube.js', <<~JS
      window.cube = function ( x ) {
        return x * x * x;
      };
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      (function () {
        'use strict';

        window.cube = function (x) {
          return x * x * x;
        };

        window.square = function (x) {
          return x * x;
        };

        console.log(square(cube(5)));

      }());
    FILE
  end

  test 'import glob via /* as array' do
    $d = true
    file 'main.js', <<~JS
      import maths from 'maths/*';

      let x = 1;
      for (var i = 0; i < maths.length; i++) {
        x = maths[i](x);
      }
      console.log(x);
    JS
    
    file 'maths/square.js', <<~JS
      export default function square ( x ) {
        return x * x;
      };
    JS
    
    file 'maths/cube.js', <<~JS
      export default function cube ( x ) {
        return x * x * x;
      };
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      (function () {
        'use strict';

        function cube(x) {
          return x * x * x;
        }

        function square(x) {
          return x * x;
        }

        var maths = [cube, square];

        let x = 1;

        for (var i = 0; i < maths.length; i++) {
          x = maths[i](x);
        }

        console.log(x);

      }());
    FILE
    $d = false
  end

end
