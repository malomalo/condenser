require 'test_helper'

class CondenserBabelTest < ActiveSupport::TestCase
  
  def setup
    super
    register_babel
  end

  def register_babel
    @env.unregister_preprocessor('application/javascript', Condenser::JSAnalyzer)
    @env.register_preprocessor 'application/javascript', Condenser::BabelProcessor.new(@npm_dir,
      presets: [ ['@babel/preset-env', { modules: false, targets: { browsers: 'firefox > 41' } }] ]
    )
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@npm_dir))
  end
  
  test 'find' do
    file 'name.js', <<~JS
    var t = { 'var': () => { return 2; } };
    
    export {t as name1};
    JS

    assert_file 'name.js', 'application/javascript', <<~JS
    var t = {
      'var': function _var() {
        return 2;
      }
    };
    export { t as name1 };
    JS
  end

  test "dependency tracking for a export from" do
    file 'c.js', <<~JS
    function c() { return 'ok'; }
    
    export {c}
    JS
    
    file 'b.js', <<~JS
    export {c} from 'c';
    
    JS
    
    file 'a.js', <<~JS
    import {c} from 'b'
    
    console.log(c());
    JS

    asset = assert_file 'a.js', 'application/javascript'
    assert_equal ['/a.js', '/b.js', '/c.js'], asset.all_export_dependencies.map { |path| path.delete_prefix(@path) }
  end

  test "error" do
    file 'error.js', <<~JS
      console.log('this file has an error');
      
      var error = {;
    JS

    e = assert_raises Condenser::SyntaxError do
      assert_file 'error.js', 'application/javascript'
    end
    assert_equal <<~ERROR.rstrip, e.message.rstrip
      /assets/error.js: Unexpected token (3:13)

        1 | console.log('this file has an error');
        2 |
      > 3 | var error = {;
          |              ^
        4 |
    ERROR
    assert_equal '/assets/error.js', e.path
  end

  test 'not duplicating polyfills' do
    file 'a.js', <<-JS
      export default function () {
        console.log(Object.hasOwn({a: 1}, "a"))
      };
    JS
    file 'b.js', <<-JS
      export default function () {
        console.log(Object.hasOwn({b: 1}, "b"))
      };
    JS
    file 'c.js', <<~JS
      import a from 'a';
      import b from 'b';

      a();
      b();
    JS

    source = assert_exported_file('c.js', 'application/javascript').source

    # core-js's Object.hasOwn polyfill is bundled once and shared by a and b
    assert_equal 1, source.scan("(store.versions || (store.versions = [])).push").size
    assert_equal 1, source.scan(/^var import_has_own = /).size
    assert source.rstrip.end_with?(<<~JS.rstrip)
      function a_default() {
      \tconsole.log((0, import_has_own.default)({ a: 1 }, "a"));
      }
      // b.js
      function b_default() {
      \tconsole.log((0, import_has_own.default)({ b: 1 }, "b"));
      }
      // c.js
      a_default();
      b_default();
    JS
  end
  
  test 'npm modules also get babelized' do
    file "#{@npm_path}/module/name.js", <<~JS
      export default function x(y) { return y?.z; }
    JS
  
    file 'name.js', <<~JS
      import x from 'module/name';
  
      var d = {};
      console.log(x(d?.z));
    JS
  
    assert_exported_file 'name.js', 'application/javascript', <<~JS
      // module/name.js
      function x(y) {
      \treturn y === null || y === void 0 ? void 0 : y.z;
      }
      // name.js
      var d = {};
      console.log(x(d === null || d === void 0 ? void 0 : d.z));
    JS

  end

  test 'depends_on a ! path, a file relative to base that is not an asset' do
    root = File.realpath(Dir.mktmpdir)
    @env = Condenser.new(@path, logger: @env.logger, npm_path: @npm_dir, base: root, listen: false)
    register_babel
    file 'config/x.yml', "secret: one\n", base: root
    file 'name.js', <<~JS
      // depends_on !config/x.yml
      console.log(1);
    JS

    asset = @env.find('name.js')
    assert_equal [File.join(root, 'config/x.yml')], asset.file_dependencies
    assert_equal [], asset.process_dependencies

    file 'missing.js', <<~JS
      // depends_on config/missing.yml
      console.log(1);
    JS
    error = assert_raises(Condenser::FileNotFound) { @env.find('missing.js').process }
    assert_equal "missing.js: couldn't find 'config/missing.yml' for // depends_on (use '!config/missing.yml' for a file relative to the app root)", error.message
  ensure
    FileUtils.remove_entry(root, true)
  end

  test 'the default plugins with the packages it installs into an empty npm path' do
    npm = File.realpath(Dir.mktmpdir)
    @env.unregister_preprocessor('application/javascript', Condenser::BabelProcessor)
    @env.register_preprocessor 'application/javascript', Condenser::BabelProcessor.new(npm,
      presets: [ ['@babel/preset-env', { modules: false, targets: { browsers: 'firefox > 41' } }] ]
    )
    file 'name.js', <<~JS
      export default async function (x) { return [...x].findLast((y) => y?.z); }
    JS

    source = @env.find('name.js').source
    assert_match %r{^import _asyncToGenerator from "@babel/runtime-corejs3/helpers/asyncToGenerator";$}, source
    assert_match %r{^import _findLastInstanceProperty from "core-js-pure/stable/instance/find-last.js";$}, source
    assert Dir.exist?(File.join(npm, 'node_modules/@babel/runtime-corejs3/helpers'))
    assert Dir.exist?(File.join(npm, 'node_modules/core-js-pure/stable/instance'))
    assert_equal '8', JSON.parse(File.read(File.join(npm, 'node_modules/@babel/core/package.json')))['version'].split('.')[0]
  ensure
    FileUtils.remove_entry(npm, true) if npm
  end

  test 'an npm path with a package.json from Babel 7 and no node_modules installs Babel 7' do
    npm = File.realpath(Dir.mktmpdir)
    File.write(File.join(npm, 'package.json'), JSON.generate({ dependencies: {
      '@babel/core' => '^7.29.0',
      '@babel/preset-env' => '^7.29.0',
      '@babel/plugin-transform-runtime' => '^7.29.0',
      '@babel/runtime-corejs3' => '^7.29.0'
    } }))
    @env.unregister_preprocessor('application/javascript', Condenser::BabelProcessor)
    @env.register_preprocessor 'application/javascript', Condenser::BabelProcessor.new(npm,
      presets: [ ['@babel/preset-env', { modules: false, targets: { browsers: 'firefox > 41' } }] ]
    )
    file 'name.js', <<~JS
      export default function (x) { return x?.y; }
    JS

    assert_file 'name.js', 'application/javascript', <<~JS
      export default function (x) {
        return x === null || x === void 0 ? void 0 : x.y;
      }
    JS
    %w[@babel/core @babel/preset-env @babel/plugin-transform-runtime @babel/runtime-corejs3].each do |name|
      assert_equal '7', JSON.parse(File.read(File.join(npm, 'node_modules', name, 'package.json')))['version'].split('.')[0]
    end
  ensure
    FileUtils.remove_entry(npm, true) if npm
  end

end

