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
    assert_equal asset.instance_variable_get(:@process_dependencies).to_a, [["models/*", ["application/javascript"]],["helpers/*", ["application/javascript"]]]


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
    assert_equal asset.instance_variable_get(:@process_dependencies).to_a, [["models/*", ["application/javascript"]],["helpers/*", ["application/javascript"]]]


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

  test 'js depending on another file type with JSAnalzyer' do
    @env.unregister_preprocessor 'application/javascript', Condenser::BabelProcessor
    @env.register_preprocessor 'application/javascript', Condenser::JSAnalyzer
    @env.unregister_minifier('application/javascript')

    file 'a.js', ''
    file 'b.rb', ''
    file 'models/a.js', ''
    file 'models/b.rb', ''

    file 'name.js.erb', <<~JS
      // depends_on **/*.rb

      console.log([<%= Dir.children("#{@path}").sort.map(&:inspect).join(', ') %>]);
    JS

    asset = @env.find('name.js')
    assert_equal asset.instance_variable_get(:@process_dependencies).to_a, [["**/*", ["application/ruby"]]]
    assert_equal asset.process_dependencies.map(&:source_file), ["#{@path}/b.rb", "#{@path}/models/b.rb"]
  end

  test 'relative imports with JSAnalzyer' do
    @env.unregister_preprocessor 'application/javascript', Condenser::BabelProcessor
    @env.register_preprocessor 'application/javascript', Condenser::JSAnalyzer
    @env.unregister_minifier('application/javascript')
    
    file 'a/a.js', <<~JS
      export decault function () { console.log("a/a"); }
    JS
    file 'b/a.js', <<~JS
      export decault function () { console.log("a/a"); }
    JS

    file 'a/b.js', <<~JS
      import fn from './a';
      a();
      console.log("a/b");
    JS
    file 'b/b.js', <<~JS
      import fn from './a';
      a();
      console.log("b/b");
    JS
    
    asset = @env.find('a/b.js')
    assert_equal asset.instance_variable_get(:@export_dependencies).to_a, [["#{@path}/a/a", ["application/javascript"]]]
    assert_equal asset.export_dependencies.map(&:source_file), ["#{@path}/a/a.js"]
  end
  
end