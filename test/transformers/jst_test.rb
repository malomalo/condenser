require 'test_helper'

class JSTTransformerTest < ActiveSupport::TestCase

  def setup
    super
    @env.unregister_preprocessor 'application/javascript', Condenser::BabelProcessor
  end
  
  test 'jst transoformation' do
    file 'test.jst', <<~SCSS
      import {escape} from 'ejs';
      export default function (locals) {
          var __output = [], __append = __output.push.bind(__output);
              __append("<div class=\\"uniformLoader\\n");
               if(typeof transparent != "undefined") {
              __append(" -transparent");
               }
              __append("\\n");
               if(typeof cover != "undefined") {
              __append(" -cover");
               }
              __append("\\n");
               if(typeof light != "undefined") {
              __append(" -light");
               }
              __append(" ");
              __append( klass );
              __append("\\">\\n    <div class=\\"uniformLoader-container\\">\\n        <span></span>\\n        <span></span>\\n        <span></span>\\n    </div>\\n</div>");
          return __output.join("");
      }
    SCSS

    assert_file 'test.js', 'application/javascript', <<~JS
    import { escape } from 'ejs';
    export default function (locals) {
      var __output = [],
          __append = __output.push.bind(__output);

      __append("<div class=\\"uniformLoader\\n");

      if (typeof locals.transparent != "undefined") {
        __append(" -transparent");
      }

      __append("\\n");

      if (typeof locals.cover != "undefined") {
        __append(" -cover");
      }

      __append("\\n");

      if (typeof locals.light != "undefined") {
        __append(" -light");
      }

      __append(" ");

      __append(locals.klass);

      __append("\\">\\n    <div class=\\"uniformLoader-container\\">\\n        <span></span>\\n        <span></span>\\n        <span></span>\\n    </div>\\n</div>");

      return __output.join("");
    }
    JS
  end

  test 'jst transoformation with object' do
    file 'test.jst', <<~SCSS
      import {append as __ejx_append} from 'ejx';
      export default function (locals) {
          var __output = [];
          __ejx_append(avatarTemplate({ account: account }), __output);
          return __output;
      }
    SCSS

    assert_file 'test.js', 'application/javascript', <<~JS
      import { append as __ejx_append } from 'ejx';
      export default function (locals) {
        var __output = [];

        __ejx_append(locals.avatarTemplate({
          account: locals.account
        }), __output);

        return __output;
      }
    JS
  end

  test 'jst with transoformation with object' do
    file 'test.jst', <<~SCSS
      import {append as __ejx_append} from 'ejx';
      export default function (locals) {
          var __output = [];
          
          function x(files) {
            return files.test();
          }
          
          class B {
          }
          
          __ejx_append(avatarTemplate({ account: x(files), klass: B }), __output);
          return __output;
      }
    SCSS

    assert_file 'test.js', 'application/javascript', <<~JS
      import { append as __ejx_append } from 'ejx';
      export default function (locals) {
        var __output = [];

        function x(files) {
          return files.test();
        }
      
        class B {}
      
        __ejx_append(locals.avatarTemplate({
          account: x(locals.files),
          klass: B
        }), __output);
      
        return __output;
      }
    JS
  end

end