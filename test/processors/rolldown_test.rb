require 'test_helper'

class RolldownTest < ActiveSupport::TestCase

  module PopenSpy
    def popen(*args, **kwargs, &block)
      super.tap { |io| Thread.current[:popen_pids]&.push(io.pid) }
    end
  end
  IO.singleton_class.prepend(PopenSpy)
  
  def setup
    super
    @env.unregister_minifier('application/javascript')
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path))
  end
  
  test 'file is exported as module' do
    file 'main.js', <<~JS
      console.log( cube( 5 ) ); // 125
    JS
    
    asset = assert_exported_file 'main.js', 'application/javascript', <<~FILE
      //#region main.js
      console.log(cube(5));
      //#endregion
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
      //#region math.js
      function cube(x) {
      	return x * x * x;
      }
      //#endregion
      //#region main.js
      console.log(cube(5));
      //#endregion
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
      //#region math.js.erb
      function cube(x) {
      	return 2 * x * x;
      }
      //#endregion
      //#region main.js
      console.log(cube(5));
      //#endregion
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
      //#region b/math.js
      function cube(x) {
      	return x * x * x;
      }
      //#endregion
      //#region a/main.js
      console.log(cube(5));
      //#endregion
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
      //#region maths/cube.js
      window.cube = function(x) {
      	return x * x * x;
      };
      //#endregion
      //#region maths/square.js
      window.square = function(x) {
      	return x * x;
      };
      //#endregion
      //#region main.js
      console.log(square(cube(5)));
      //#endregion
    FILE
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

    assert_exported_file 'main.js', 'application/javascript', <<~'FILE'
      //#region maths/cube.js
      function cube(x) {
      	return x * x * x;
      }
      //#endregion
      //#region maths/square.js
      function square(x) {
      	return x * x;
      }
      //#endregion
      //#region \0condenser-glob:maths/*
      var __default = [cube, square];
      //#endregion
      //#region main.js
      var x = 1;
      for (var i = 0; i < __default.length; i++) x = __default[i](x);
      console.log(x);
      //#endregion
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
      //#region module/base.js
      var Base = class {};
      //#endregion
      //#region module/base/other.js
      var Lower = class extends Base {};
      //#endregion
      //#region main.js
      console.log(Base, Lower);
      //#endregion
    FILE
  end

  test 'an error raised in ruby stops the node process' do
    file 'main.js', <<~JS
      import maths from 'maths/*';

      console.log( maths );
    JS
    file 'maths/cube.js', <<~JS
      export default function cube ( x ) {
        return x * x * x;
      };
    JS
    Condenser::Asset.any_instance.stubs(:has_default_export?).raises(RuntimeError, 'boom')

    pids = Thread.current[:popen_pids] = []
    error = assert_raises(RuntimeError) { @env.find('main.js').export }
    assert_equal 'boom', error.message
    assert_equal 1, pids.size
    assert_raises(Errno::ESRCH) { Process.kill(0, pids.first) }
  ensure
    Thread.current[:popen_pids] = nil
    pids&.each { |pid| Process.kill('KILL', pid) rescue nil }
  end

end
