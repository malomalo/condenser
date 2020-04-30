require 'test_helper'

class CondenserEJSTest < ActiveSupport::TestCase

  test 'find' do
    file 'test.jst.ejs', "1<%= 1 + 1 %>3\n"
    
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
    file 'test.jst.ejs', "1<%= input %>3\n"
    
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

  test 'loading a cached file alsos initializes the processors' do
    cache_dir = File.join(@path, 'cache')
    Dir.mkdir(cache_dir)
    @env.cache = Condenser::Cache::FileStore.new(cache_dir)

    file 'test.jst.ejs', "1<%= 1 + 1 %>3\n"
    file 'render.js', <<~JS
      import template from 'test';
      console.log(template());
    JS
    assert_file 'test.js', 'application/javascript'
    
    @env = Condenser.new(@path,
      logger: Logger.new('/dev/null'),
      cache: Condenser::Cache::FileStore.new(cache_dir),
      pipeline: false
    )
    @env.register_exporter('application/javascript', Condenser::RollupProcessor)
    
    assert_exported_file 'render.js', 'application/javascript'
  end
end
