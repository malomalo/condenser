require 'test_helper'

class CondenserEJSTest < ActiveSupport::TestCase

  def setup
    super
    @env.unregister_preprocessor('application/javascript', Condenser::BabelProcessor)
  end
  
  test 'find' do
    file 'test.ejs', "1<%= 1 + 1 %>3\n"
    
    assert_file 'test.js', 'application/javascript', <<~JS
      import _bindInstanceProperty from "@babel/runtime-corejs3/core-js-stable/instance/bind";
      import { escape } from 'ejs';
      export default function (locals) {
        var _context;

        var __output = [],
            __append = _bindInstanceProperty(_context = __output.push).call(_context, __output);
      
        __append("1");
      
        __append(escape(1 + 1));
      
        __append("3\\n");
      
        return __output.join("");
      }
    JS
  end
  
  test 'locals' do
    file 'test.ejs', "1<%= input %>3\n"
    
    assert_file 'test.js', 'application/javascript', <<~JS
      import _bindInstanceProperty from "@babel/runtime-corejs3/core-js-stable/instance/bind";
      import { escape } from 'ejs';
      export default function (locals) {
        var _context;

        var __output = [],
            __append = _bindInstanceProperty(_context = __output.push).call(_context, __output);
      
        __append("1");
      
        __append(escape(locals.input));
      
        __append("3\\n");
      
        return __output.join("");
      }
    JS
  end

end
