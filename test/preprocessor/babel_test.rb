require 'test_helper'

class CondenserBabelTest < ActiveSupport::TestCase
  
  test 'find' do
    file 'name.js', <<~JS
    var t = { 'var': () => { return 2; } };
    
    export {t as name1};
    JS

    assert_file 'name.js', 'application/javascript', <<~JS
    var t = { 'var': function _var() {
        return 2;
      } };
    
    export { t as name1 };
    JS
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

    assert_file 'a.js', 'application/javascript', <<~JS
      export { t as name1 };
    JS
  end
  
end
