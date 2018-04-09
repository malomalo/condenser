require 'test_helper'

class SassMinifierTest < ActiveSupport::TestCase

  test 'simple example' do
    file 'test.css', <<~JS
      * {
        background: #FFFFFF;
      }
    JS
    
    assert_exported_file 'test.css', 'text/css', <<~CSS
      *{background:#FFFFFF}
    CSS
  end
  
end
