require 'test_helper'

class RollupDynamicImportTestTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.unregister_minifier('application/javascript')
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
      function cube$1 ( x ) {
        return x * x * x;
      }

      const math = /*#__PURE__*/Object.freeze(/*#__PURE__*/Object.defineProperty({
        __proto__: null,
        cube: cube$1
      }, Symbol.toStringTag, { value: 'Module' }));

      x;

      const b = /*#__PURE__*/Object.freeze(/*#__PURE__*/Object.defineProperty({
        __proto__: null,
        cube: cube$1
      }, Symbol.toStringTag, { value: 'Module' }));

      cube = await Promise.resolve().then(() => math);
      bigCube = await Promise.resolve().then(() => b);

      console.log( cube( 5 ) ); // 125
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
    @env.register_exporter 'application/javascript', Condenser::RollupProcessor.new(@env.npm_path, dynamic_imports: false)

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
      cube = await import('/#{@env.find('math/math').path}');
      bigCube = await import('/#{@env.find('math/b').path}');

      console.log( cube( 5 ) ); // 125
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
      assert_equal 240, data['main.js']['size']
      assert_equal main.path, data['main.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['main.js']['path'])).rstrip)
        cube = await import('/#{math.path}');
        bigCube = await import('/#{mathb.path}');

        console.log( cube( 5 ) ); // 125
      JS

      assert data['math/math.js']
      assert_equal 62, data['math/math.js']['size']
      assert_equal math.path, data['math/math.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/math.js']['path'])).rstrip)
        function cube ( x ) {
          return x * x * x;
        }

        export { cube };
      JS

      assert data['math/b.js']
      assert_equal 66, data['math/b.js']['size']
      assert_equal mathb.path, data['math/b.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/b.js']['path'])).rstrip)
        function cube ( x ) {
          return x * x * x;
        }

        x;

        export { cube };
      JS
    end
  end

  test "dynamic imports with a prefix" do
    @env.unregister_exporter 'application/javascript'
    @env.register_exporter 'application/javascript', Condenser::RollupProcessor.new(@env.npm_path, prefix: "/assets", dynamic_imports: false)

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
      cube = await import('/assets/#{@env.find('math/math').path}');
      bigCube = await import('/assets/#{@env.find('math/b').path}');

      console.log( cube( 5 ) ); // 125
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
      assert_equal 254, data['main.js']['size']
      assert_equal main.path, data['main.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['main.js']['path'])).rstrip)
        cube = await import('/assets/#{math.path}');
        bigCube = await import('/assets/#{mathb.path}');

        console.log( cube( 5 ) ); // 125
      JS

      assert data['math/math.js']
      assert_equal 62, data['math/math.js']['size']
      assert_equal math.path, data['math/math.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/math.js']['path'])).rstrip)
        function cube ( x ) {
          return x * x * x;
        }

        export { cube };
      JS

      assert data['math/b.js']
      assert_equal 66, data['math/b.js']['size']
      assert_equal mathb.path, data['math/b.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/b.js']['path'])).rstrip)
        function cube ( x ) {
          return x * x * x;
        }

        x;

        export { cube };
      JS
    end
  end

  test "cyclical dynamic imports don't inlined and are exported" do
    @env.unregister_exporter 'application/javascript'
    @env.register_exporter 'application/javascript', Condenser::RollupProcessor.new(@env.npm_path, dynamic_imports: false)

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
      const cube = await import('/#{@env.find('/math/math').export.path}');

      console.log( cube( 5 ) ); // 125
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
      assert_equal 143, data['main.js']['size']
      assert_equal main.path, data['main.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['main.js']['path'])).rstrip)
        const cube = await import('/#{math.path}');

        console.log( cube( 5 ) ); // 125
      JS

      assert data['math/math.js']
      assert_equal 336, data['math/math.js']['size']
      assert_equal math.path, data['math/math.js']['path']
      assert_equal(<<~JS.rstrip, File.read(File.join(export_dir, data['math/math.js']['path'])).rstrip)
        const math = await Promise.resolve().then(() => entry);

        function cube ( x ) {
          return math.number(x) * x * x;
        }

        function number (x) { return x; }

        const entry = /*#__PURE__*/Object.freeze(/*#__PURE__*/Object.defineProperty({
          __proto__: null,
          cube,
          number
        }, Symbol.toStringTag, { value: 'Module' }));

        export { cube, number };
      JS
    end
  end

  #TODO: add test for inilne / not inline URLs

end
