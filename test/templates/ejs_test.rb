require 'test_helper'

class CondenserEJSTest < ActiveSupport::TestCase

  def setup
    super
    @env.unregister_preprocessor('application/javascript', Condenser::BabelProcessor)
  end
  
  test 'find' do
    file 'test.ejs', "1<%= 1 + 1 %>3\n"
    
    assert_file 'test.js', 'application/javascript', <<~JS
      import {escape} from 'ejs';
      export default function (locals) {
          var __output = [], __append = __output.push.bind(__output);
          with (locals || {}) {
              __append(`1`);
              __append(escape( 1 + 1 ));
              __append(`3\\n`);
          }
          return __output.join("");
      }
    JS
  end
  
end