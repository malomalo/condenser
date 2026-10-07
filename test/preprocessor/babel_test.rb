require 'test_helper'

class CondenserBabelTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.unregister_preprocessor('application/javascript', Condenser::JSAnalyzer)
    @env.register_preprocessor 'application/javascript', Condenser::BabelProcessor.new(@npm_dir,
      presets: [ ['@babel/preset-env', { modules: false, targets: { browsers: 'firefox > 41' } }] ]
    )
    @env.unregister_minifier    'application/javascript'
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
        console.log(Object.assign({}, {a: 1}))
      };
    JS
    file 'b.js', <<-JS
      export default function () {
        console.log(Object.assign({}, {b: 1}))
      };
    JS
    file 'c.js', <<~JS
      import a from 'a';
      import b from 'b';

      a();
      b();
    JS

    source = assert_exported_file('c.js', 'application/javascript').source

    # core-js's Object.assign polyfill is bundled once and shared by a and b
    assert_equal 1, source.scan("(store.versions || (store.versions = [])).push").size
    assert_equal 1, source.scan(/^const _Object\$assign = /).size
    assert source.rstrip.end_with?(<<~JS.rstrip)
      function a () {
        console.log(_Object$assign({}, {
          a: 1
        }));
      }

      function b () {
        console.log(_Object$assign({}, {
          b: 1
        }));
      }

      a();
      b();
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
      function x(y) {
        return y === null || y === void 0 ? void 0 : y.z;
      }

      var d = {};
      console.log(x(d === null || d === void 0 ? void 0 : d.z));
    JS
  
  end
end