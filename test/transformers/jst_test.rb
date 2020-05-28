require 'test_helper'

class JSTTransformerTest < ActiveSupport::TestCase

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
    import _bindInstanceProperty from "@babel/runtime-corejs3/core-js-stable/instance/bind";
    import { escape } from 'ejs';
    export default function (locals) {
      var _context;

      var __output = [],
          __append = _bindInstanceProperty(_context = __output.push).call(_context, __output);

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

end