require 'test_helper'

ESBUILD = ENV['CONDENSER_ESBUILD_PATH'] || '/private/tmp/claude-501/-Users-malomalo-Code-scratch-surveys/e1bf4d1d-31a0-4fa2-b1c0-e9e72409416c/scratchpad/bench/node_modules/esbuild' unless defined?(ESBUILD)

# Copied from rollup/dynamic_import_test.rb, with the expected output changed
# to esbuild's formatting where the bundled code is the same.
class EsbuildDynamicImportTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.unregister_minifier('application/javascript')
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::EsbuildProcessor.new(@env.npm_path, bundler_path: ESBUILD))
  end
 
  test 'dynamic imports get inlined' do
    file 'main.js', <<~JS
      cube = await import('./math/math');
      bigCube = await import('math/b');

      console.log( cube( 5 ) ); // 125
    JS

    file 'math/cube.js', <<~JS
      export default function cube ( x ) {
        return x * x * x;
      }
    JS
    file 'math/math.js', <<~JS
      import cube from './cube';

      export {cube};
    JS
    file 'math/b.js', <<~JS
      import cube from './cube';
      let b = x;
      export {cube};
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      var __defProp = Object.defineProperty;
      var __getOwnPropNames = Object.getOwnPropertyNames;
      var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
      var __esm = (fn, res, err) => function __init() {
        if (err) throw err[0];
        try {
          return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
        } catch (e) {
          throw err = [e], e;
        }
      };
      var __export = (target, all) => {
        for (var name in all)
          __defProp(target, name, { get: all[name], enumerable: true });
      };

      function cube2(x2) {
        return x2 * x2 * x2;
      }
      var init_cube = __esm({
        "condenser:math/cube.js"() {
          __name(cube2, "cube");
        }
      });

      var math_exports = {};
      __export(math_exports, {
        cube: () => cube2
      });
      var init_math = __esm({
        "condenser:math/math.js"() {
          init_cube();
        }
      });

      var b_exports = {};
      __export(b_exports, {
        cube: () => cube2
      });
      var b;
      var init_b = __esm({
        "condenser:math/b.js"() {
          init_cube();
          b = x;
        }
      });

      cube = await Promise.resolve().then(() => (init_math(), math_exports));
      bigCube = await Promise.resolve().then(() => (init_b(), b_exports));
      console.log(cube(5));
    FILE
  end

  test 'file with dynamic imports' do
    1.upto(3) do |i|
      if i == 3
        file "module-name/path/to/specific/un-exported/file#{i}.js", "#{i}"
      else
        file "module-name#{i}.js", "#{i}"
      end
    end

    file 'name.js', <<~JS
      let x = await import("module-name1");
      let y = import("module-name2");
      import("module-name/path/to/specific/un-exported/file3");
    JS

    asset = @env.find('name.js')
    assert_nil asset.exports
    assert_equal [
      "module-name1.js",
      "module-name2.js",
      "module-name/path/to/specific/un-exported/file3.js"
    ], asset.linked_assets.map(&:filename)
  end

  test "dynamic imports don't inlined and are exported" do
    @env.unregister_exporter 'application/javascript'
    @env.register_exporter 'application/javascript', Condenser::EsbuildProcessor.new(@env.npm_path, bundler_path: ESBUILD, dynamic_imports: false)

    file 'main.js', <<~JS
      cube = await import('./math/math');
      bigCube = await import('math/b');

      console.log( cube( 5 ) ); // 125
    JS

    file 'math/cube.js', <<~JS
      export default function cube ( x ) {
        return x * x * x;
      }
    JS
    file 'math/math.js', <<~JS
      import cube from './cube';

      export {cube};
    JS
    file 'math/b.js', <<~JS
      import cube from './cube';
      let b = x;
      export {cube};
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      cube = await import("/#{@env.find('math/math').path}");
      bigCube = await import("/#{@env.find('math/b').path}");
      console.log(cube(5));
    FILE

    Dir.mktmpdir do |export_dir|
      manifest = Condenser::Manifest.new(@env, File.join(export_dir, 'manifest.json'))
      main = @env['main.js']
      math = @env['math/math.js']
      mathb = @env['math/b.js']
      assets = [main, math, mathb]

      assets.each do |asset|
        assert !File.exist?("#{export_dir}/#{asset.path}")
      end

      manifest.compile('main.js')
      assert File.directory?(manifest.dir)
      assert File.file?(manifest.filename)
      assert File.exist?("#{export_dir}/manifest.json")

      assets.each do |asset|
        assert File.exist?("#{export_dir}/#{asset.path}")
        assert File.exist?("#{export_dir}/#{asset.path}.gz")
      end

      data = JSON.parse(File.read(manifest.filename))

      assert data['main.js']
      assert_equal 228, data['main.js']['size']
      assert_equal main.path, data['main.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['main.js']['path'])).rstrip)
        cube = await import("/#{math.path}");
        bigCube = await import("/#{mathb.path}");
        console.log(cube(5));
      JS

      assert data['math/math.js']
      assert_equal 212, data['math/math.js']['size']
      assert_equal math.path, data['math/math.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/math.js']['path'])).rstrip)
        var __defProp = Object.defineProperty;
        var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

        function cube(x) {
          return x * x * x;
        }
        __name(cube, "cube");
        export {
          cube
        };
      JS

      assert data['math/b.js']
      assert_equal 228, data['math/b.js']['size']
      assert_equal mathb.path, data['math/b.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/b.js']['path'])).rstrip)
        var __defProp = Object.defineProperty;
        var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

        function cube(x2) {
          return x2 * x2 * x2;
        }
        __name(cube, "cube");

        var b = x;
        export {
          cube
        };
      JS
    end
  end

  test "dynamic imports with a prefix" do
    @env.unregister_exporter 'application/javascript'
    @env.register_exporter 'application/javascript', Condenser::EsbuildProcessor.new(@env.npm_path, bundler_path: ESBUILD, prefix: "/assets", dynamic_imports: false)

    file 'main.js', <<~JS
      cube = await import('./math/math');
      bigCube = await import('math/b');

      console.log( cube( 5 ) ); // 125
    JS

    file 'math/cube.js', <<~JS
      export default function cube ( x ) {
        return x * x * x;
      }
    JS
    file 'math/math.js', <<~JS
      import cube from './cube';

      export {cube};
    JS
    file 'math/b.js', <<~JS
      import cube from './cube';
      let b = x;
      export {cube};
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      cube = await import("/assets/#{@env.find('math/math').path}");
      bigCube = await import("/assets/#{@env.find('math/b').path}");
      console.log(cube(5));
    FILE

    Dir.mktmpdir do |export_dir|
      manifest = Condenser::Manifest.new(@env, File.join(export_dir, 'manifest.json'))
      main = @env['main.js']
      math = @env['math/math.js']
      mathb = @env['math/b.js']
      assets = [main, math, mathb]

      assets.each do |asset|
        assert !File.exist?("#{export_dir}/#{asset.path}")
      end

      manifest.compile('main.js')
      assert File.directory?(manifest.dir)
      assert File.file?(manifest.filename)
      assert File.exist?("#{export_dir}/manifest.json")

      assets.each do |asset|
        assert File.exist?("#{export_dir}/#{asset.path}")
        assert File.exist?("#{export_dir}/#{asset.path}.gz")
      end

      data = JSON.parse(File.read(manifest.filename))

      assert data['main.js']
      assert_equal 242, data['main.js']['size']
      assert_equal main.path, data['main.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['main.js']['path'])).rstrip)
        cube = await import("/assets/#{math.path}");
        bigCube = await import("/assets/#{mathb.path}");
        console.log(cube(5));
      JS

      assert data['math/math.js']
      assert_equal 212, data['math/math.js']['size']
      assert_equal math.path, data['math/math.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/math.js']['path'])).rstrip)
        var __defProp = Object.defineProperty;
        var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

        function cube(x) {
          return x * x * x;
        }
        __name(cube, "cube");
        export {
          cube
        };
      JS

      assert data['math/b.js']
      assert_equal 228, data['math/b.js']['size']
      assert_equal mathb.path, data['math/b.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/b.js']['path'])).rstrip)
        var __defProp = Object.defineProperty;
        var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

        function cube(x2) {
          return x2 * x2 * x2;
        }
        __name(cube, "cube");

        var b = x;
        export {
          cube
        };
      JS
    end
  end

  test "cyclical dynamic imports don't inlined and are exported" do
    @env.unregister_exporter 'application/javascript'
    @env.register_exporter 'application/javascript', Condenser::EsbuildProcessor.new(@env.npm_path, bundler_path: ESBUILD, dynamic_imports: false)

    file 'main.js', <<~JS
      const cube = await import('./math/math');

      console.log( cube( 5 ) ); // 125
    JS

    file 'math/cube.js', <<~JS
      const math = await import('./math');

      export default function cube ( x ) {
        return math.number(x) * x * x;
      }
    JS
    file 'math/math.js', <<~JS
      import cube from './cube';

      function number (x) { return x; }

      export {cube, number};
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      var cube = await import("/#{@env.find('/math/math').export.path}");
      console.log(cube(5));
    FILE

    Dir.mktmpdir do |export_dir|
      manifest = Condenser::Manifest.new(@env, File.join(export_dir, 'manifest.json'))
      main = @env['main.js']
      math = @env['math/math.js']
      cube = @env['math/cube.js']
      assets = [main, math]

      assets.each do |asset|
        assert !File.exist?("#{export_dir}/#{asset.path}")
      end

      manifest.compile('main.js')
      assert File.directory?(manifest.dir)
      assert File.file?(manifest.filename)
      assert File.exist?("#{export_dir}/manifest.json")

      assets.each do |asset|
        assert File.exist?("#{export_dir}/#{asset.path}")
        assert File.exist?("#{export_dir}/#{asset.path}.gz")
      end

      data = JSON.parse(File.read(manifest.filename))

      assert_equal ["main.js", "math/math.js"], data.keys

      assert data['main.js']
      assert_equal 129, data['main.js']['size']
      assert_equal main.path, data['main.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['main.js']['path'])).rstrip)
        var cube = await import("/#{math.path}");
        console.log(cube(5));
      JS

      assert data['math/math.js']
      assert_equal 1028, data['math/math.js']['size']
      assert_equal math.path, data['math/math.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/math.js']['path'])).rstrip)
        var __defProp = Object.defineProperty;
        var __getOwnPropNames = Object.getOwnPropertyNames;
        var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
        var __esm = (fn, res, err) => function __init() {
          if (err) throw err[0];
          try {
            return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
          } catch (e) {
            throw err = [e], e;
          }
        };
        var __export = (target, all) => {
          for (var name in all)
            __defProp(target, name, { get: all[name], enumerable: true });
        };

        function cube(x) {
          return math.number(x) * x * x;
        }
        var math;
        var init_cube = __esm({
          async "condenser:math/cube.js"() {
            math = await init_math().then(() => math_exports);
            __name(cube, "cube");
          }
        });

        var math_exports = {};
        __export(math_exports, {
          cube: () => cube,
          number: () => number
        });
        function number(x) {
          return x;
        }
        var init_math = __esm({
          async "condenser:math/math.js"() {
            await init_cube();
            __name(number, "number");
          }
        });
        await init_math();
        export {
          cube,
          number
        };
      JS
    end
  end

  #TODO: add test for inilne / not inline URLs

end
