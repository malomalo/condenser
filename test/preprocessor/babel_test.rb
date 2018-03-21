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
  
end
