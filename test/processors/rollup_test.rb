require 'test_helper'

class RollupTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RollupProcessor.new(@npm_dir))
  end
  
  test 'file is exported as module' do
    file 'main.js', <<~JS
      console.log( cube( 5 ) ); // 125
    JS
    
    asset = assert_exported_file 'main.js', 'application/javascript', <<~FILE
      console.log( cube( 5 ) ); // 125
    FILE
    assert_equal "module", asset.type
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
        // This function gets included
        function cube ( x ) {
          return x * x * x;
        }

        console.log( cube( 5 ) ); // 125
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
      function cube ( x ) {
        return 2 * x * x;
      }

      console.log( cube( 5 ) ); // 125
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
        function cube ( x ) {
          return x * x * x;
        }

        console.log( cube( 5 ) ); // 125
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
      window.cube = function ( x ) {
        return x * x * x;
      };

      window.square = function ( x ) {
        return x * x;
      };

      console.log( square(cube( 5 )) );
    FILE
  end

  test 'import a ./ glob relative to the importing file' do
    file 'a/router.js', <<~JS
      import controllers from './controllers/*';

      console.log( controllers );
    JS
    file 'a/controllers/x.js', "export default 'a/x';\n"
    file 'controllers/x.js', "export default 'root/x';\n"

    source = @env.find('a/router.js').export.source
    assert_includes source, "'a/x'"
    assert_not_includes source, "'root/x'"
  end

  test 'import glob via /* as array' do
    $d = true
    file 'main.js', <<~JS
      import maths from 'maths/*';

      var x = 1;
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
      function cube ( x ) {
        return x * x * x;
      }

      function square ( x ) {
        return x * x;
      }

      const maths = [cube, square];

      var x = 1;
      for (var i = 0; i < maths.length; i++) {
        x = maths[i](x);
      }
      console.log(x);
    FILE
    $d = false
  end

  test 'import the same file via relative require and full path' do
    file "#{@npm_path}/module/base.js", <<~JS
      export default class Base { };
    JS
    
    file "#{@npm_path}/module/base/other.js", <<~JS
      import Base from '../base';
      
      export default class Lower extends Base { };
    JS
    
    file 'main.js', <<~JS
      import Other from 'module/base/other';
      import Base from 'module/base';

      console.log( Base, Other );
    JS


    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      class Base { }

      class Lower extends Base { }

      console.log( Base, Lower );
    FILE
  end

  test 'using RollupProcessor logs a deprecation warning once' do
    Condenser::RollupProcessor.instance_variable_set(:@deprecation_warned, false)
    file 'a.js', "console.log( 'a' );\n"
    file 'b.js', "console.log( 'b' );\n"

    @env.logger.expects(:warn).with('Condenser::RollupProcessor is deprecated and will be removed in condenser 3.0; use Condenser::RolldownProcessor instead').once
    @env.find('a.js').export
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RollupProcessor.new(@npm_dir))
    @env.find('b.js').export
  end

  test 'the deprecation warning goes to Kernel#warn without a logger' do
    Condenser::RollupProcessor.instance_variable_set(:@deprecation_warned, false)

    assert_output('', "#{Condenser::RollupProcessor::DEPRECATION}\n") do
      Condenser::RollupProcessor.warn_deprecated(nil)
      Condenser::RollupProcessor.warn_deprecated(nil)
    end
  end

end
