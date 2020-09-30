require 'test_helper'

class DependencyTest < ActiveSupport::TestCase
  
  test 'js file with dependencies processed with BabelPorcessor' do
    @env.unregister_minifier('application/javascript')
    
    file 'models/a.js', ''
    file 'models/b.js', ''
    
    file 'helpers/a.js', ''
    
    file 'name.js.erb', <<~JS
      // depends_on models/*.js
      // depends_on helpers/*.js
      console.log([<%= Dir.children("#{@path}/models").sort.map(&:inspect).join(', ') %>]);
    JS

    asset = @env.find('name.js')
    assert_equal asset.instance_variable_get(:@process_dependencies), ["models/*.js","helpers/*.js"]


    assert_file 'name.js', 'application/javascript', <<~JS
      // depends_on models/*.js
      // depends_on helpers/*.js
      console.log(["a.js", "b.js"]);
    JS

    file 'models/c.js', ''

    assert_file 'name.js', 'application/javascript', <<~JS
      // depends_on models/*.js
      // depends_on helpers/*.js
      console.log(["a.js", "b.js", "c.js"]);
    JS
  end

  
  test 'js file with dependencies processed with JSAnalzyer' do
    @env.unregister_preprocessor 'application/javascript', Condenser::BabelProcessor
    @env.register_preprocessor 'application/javascript', Condenser::JSAnalyzer
    @env.unregister_minifier('application/javascript')
    
    file 'models/a.js', ''
    file 'models/b.js', ''
    
    file 'helpers/a.js', ''
    
    file 'name.js.erb', <<~JS
      // depends_on models/*.js
      // depends_on helpers/*.js
    
      console.log([<%= Dir.children("#{@path}/models").sort.map(&:inspect).join(', ') %>]);
    JS

    asset = @env.find('name.js')
    assert_equal asset.instance_variable_get(:@process_dependencies), ["models/*.js","helpers/*.js"]


    assert_file 'name.js', 'application/javascript', <<~JS
      // depends_on models/*.js
      // depends_on helpers/*.js

      console.log(["a.js", "b.js"]);
    JS

    file 'models/c.js', ''

    assert_file 'name.js', 'application/javascript', <<~JS
      // depends_on models/*.js
      // depends_on helpers/*.js

      console.log(["a.js", "b.js", "c.js"]);
    JS
  end

end