require 'test_helper'

class RolldownDynamicImportTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.unregister_minifier('application/javascript')
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path))
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

    # Unlike Rollup, which hoists math/b.js's side effect (`x;`) to the top of
    # the bundle, Rolldown runs each inlined module when its import() is
    # evaluated, as native dynamic imports would.
    assert_exported_file 'main.js', 'application/javascript', <<~'FILE'
      //#region \0rolldown/runtime.js
      var __defProp = Object.defineProperty;
      var __esmMin = (fn, res, err) => () => {
      	if (err) throw err[0];
      	try {
      		return fn && (res = fn(fn = 0)), res;
      	} catch (e) {
      		throw err = [e], e;
      	}
      };
      var __exportAll = (all, no_symbols) => {
      	let target = {};
      	for (var name in all) __defProp(target, name, {
      		get: all[name],
      		enumerable: true
      	});
      	if (!no_symbols) __defProp(target, Symbol.toStringTag, { value: "Module" });
      	return target;
      };
      //#endregion
      //#region math/cube.js
      function cube$1(x) {
      	return x * x * x;
      }
      var init_cube = __esmMin(() => {});
      //#endregion
      //#region math/math.js
      var math_exports = /* @__PURE__ */ __exportAll({ cube: () => cube$1 });
      var init_math = __esmMin(() => {
      	init_cube();
      });
      //#endregion
      //#region math/b.js
      var b_exports = /* @__PURE__ */ __exportAll({ cube: () => cube$1 });
      var init_b = __esmMin(() => {
      	init_cube();
      	x;
      });
      //#endregion
      //#region main.js
      cube = await Promise.resolve().then(() => (init_math(), math_exports));
      bigCube = await Promise.resolve().then(() => (init_b(), b_exports));
      console.log(cube(5));
      //#endregion
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
    @env.register_exporter 'application/javascript', Condenser::RolldownProcessor.new(@env.npm_path, dynamic_imports: false)

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
      //#region main.js
      cube = await import("/#{@env.find('math/math').path}");
      bigCube = await import("/#{@env.find('math/b').path}");
      console.log(cube(5));
      //#endregion
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
      assert_equal 259, data['main.js']['size']
      assert_equal main.path, data['main.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['main.js']['path'])).rstrip)
        //#region main.js
        cube = await import("/#{math.path}");
        bigCube = await import("/#{mathb.path}");
        console.log(cube(5));
        //#endregion
      JS

      assert data['math/math.js']
      assert_equal 93, data['math/math.js']['size']
      assert_equal math.path, data['math/math.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/math.js']['path'])).rstrip)
        //#region math/cube.js
        function cube(x) {
        	return x * x * x;
        }
        //#endregion
        export { cube };
      JS

      assert data['math/b.js']
      assert_equal 129, data['math/b.js']['size']
      assert_equal mathb.path, data['math/b.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/b.js']['path'])).rstrip)
        //#region math/cube.js
        function cube(x) {
        	return x * x * x;
        }
        //#endregion
        //#region math/b.js
        x;
        //#endregion
        export { cube };
      JS
    end
  end

  test "dynamic imports with a prefix" do
    @env.unregister_exporter 'application/javascript'
    @env.register_exporter 'application/javascript', Condenser::RolldownProcessor.new(@env.npm_path, prefix: "/assets", dynamic_imports: false)

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
      //#region main.js
      cube = await import("/assets/#{@env.find('math/math').path}");
      bigCube = await import("/assets/#{@env.find('math/b').path}");
      console.log(cube(5));
      //#endregion
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
      assert_equal 273, data['main.js']['size']
      assert_equal main.path, data['main.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['main.js']['path'])).rstrip)
        //#region main.js
        cube = await import("/assets/#{math.path}");
        bigCube = await import("/assets/#{mathb.path}");
        console.log(cube(5));
        //#endregion
      JS

      assert data['math/math.js']
      assert_equal 93, data['math/math.js']['size']
      assert_equal math.path, data['math/math.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/math.js']['path'])).rstrip)
        //#region math/cube.js
        function cube(x) {
        	return x * x * x;
        }
        //#endregion
        export { cube };
      JS

      assert data['math/b.js']
      assert_equal 129, data['math/b.js']['size']
      assert_equal mathb.path, data['math/b.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/b.js']['path'])).rstrip)
        //#region math/cube.js
        function cube(x) {
        	return x * x * x;
        }
        //#endregion
        //#region math/b.js
        x;
        //#endregion
        export { cube };
      JS
    end
  end

  test "cyclical dynamic imports don't inlined and are exported" do
    @env.unregister_exporter 'application/javascript'
    @env.register_exporter 'application/javascript', Condenser::RolldownProcessor.new(@env.npm_path, dynamic_imports: false)

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
      //#region main.js
      const cube = await import("/#{@env.find('/math/math').export.path}");
      console.log(cube(5));
      //#endregion
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
      assert_equal 162, data['main.js']['size']
      assert_equal main.path, data['main.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['main.js']['path'])).rstrip)
        //#region main.js
        const cube = await import("/#{math.path}");
        console.log(cube(5));
        //#endregion
      JS

      # math/cube.js dynamically imports math/math.js, the module being
      # exported, while math/math.js statically imports it. This output throws
      # when run ("Cannot read properties of undefined (reading 'then')"), as
      # Rollup's does ("Cannot access 'entry' before initialization"); this
      # asserts what Rolldown currently produces.
      assert data['math/math.js']
      assert_equal 951, data['math/math.js']['size']
      assert_equal math.path, data['math/math.js']['path']
      assert_equal(<<~'JS'.rstrip, File.read(File.join(export_dir, data['math/math.js']['path'])).rstrip)
        //#region \0rolldown/runtime.js
        var __defProp = Object.defineProperty;
        var __esmMin = (fn, res, err) => () => {
        	if (err) throw err[0];
        	try {
        		return fn && (res = fn(fn = 0)), res;
        	} catch (e) {
        		throw err = [e], e;
        	}
        };
        var __exportAll = (all, no_symbols) => {
        	let target = {};
        	for (var name in all) __defProp(target, name, {
        		get: all[name],
        		enumerable: true
        	});
        	if (!no_symbols) __defProp(target, Symbol.toStringTag, { value: "Module" });
        	return target;
        };
        //#endregion
        //#region math/cube.js
        function cube(x) {
        	return math.number(x) * x * x;
        }
        var math;
        var init_cube = __esmMin(async () => {
        	math = await init_math().then(() => math_exports);
        });
        //#endregion
        //#region math/math.js
        var math_exports = /* @__PURE__ */ __exportAll({
        	cube: () => cube,
        	number: () => number
        });
        function number(x) {
        	return x;
        }
        var init_math = __esmMin(async () => {
        	await init_cube();
        });
        //#endregion
        await init_math();
        export { cube, number };
      JS
    end
  end

  #TODO: add test for inilne / not inline URLs

end
