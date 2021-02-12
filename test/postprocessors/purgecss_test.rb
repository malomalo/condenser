require 'test_helper'

class PurgeCSSTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.register_postprocessor('text/css', Condenser::PurgeCSSProcessor)
    @env.unregister_minifier('text/css')
  end
  
  test 'purge from html' do
    file 'main.css', <<~CSS
      .test{
        display: block;
      }
      .test2{
        display: inline;
      }
    CSS
    file 'index.html', <<~HTML
      <div class="test2"></div>
    HTML

    assert_exported_file 'main.css', 'text/css', <<~FILE
    .test2{
      display: inline;
    }
    FILE
  end
  
  test 'purge from js' do
    file 'main.css', <<~CSS
      .test{
        display: block;
      }
      .test2{
        display: inline;
      }
      .test3{
        display: inline-block;
      }
    CSS
    file 'main.js', <<~HTML
      document.getElementById('foo').classList.add('test3', 'test2');
    HTML

    assert_exported_file 'main.css', 'text/css', <<~FILE
    .test2{
      display: inline;
    }
    .test3{
      display: inline-block;
    }
    FILE
  end
  
  test 'purge from js with space separated classes' do
    file 'main.css', <<~CSS
      .test{
        display: block;
      }
      .test2{
        display: inline;
      }
      .test3{
        display: inline-block;
      }
    CSS
    file 'main.js', <<~HTML
      document.getElementById('foo').setAttribute('class', 'test3 test2');
    HTML

    assert_exported_file 'main.css', 'text/css', <<~FILE
    .test2{
      display: inline;
    }
    .test3{
      display: inline-block;
    }
    FILE
  end
  
  test 'purge from html with class with /' do
    file 'main.css', <<~CSS
      .test{
        display: block;
      }
      .test2-1\\/2{
        display: inline;
      }
    CSS
    file 'index.html', <<~HTML
      <div class="test2-1/2"></div>
    HTML

    assert_exported_file 'main.css', 'text/css', <<~FILE
    .test2-1\\/2{
      display: inline;
    }
    FILE
  end
  
  test 'purge from html with nested tags' do
    file 'main.css', <<~CSS
      .test pre{
        display: block;
      }
    CSS
    file 'index.html', <<~HTML
      <div class="test">
        <pre>Test</pre>
      </div>
    HTML

    assert_exported_file 'main.css', 'text/css', <<~FILE
    .test pre{
      display: block;
    }
    FILE
  end

end
