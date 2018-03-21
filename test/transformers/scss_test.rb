require 'test_helper'

class CondenserSCSSTest < ActiveSupport::TestCase

  test 'find' do
    file 'test.scss', <<~SCSS
    body {
      background-color: green;
      
      &:hover {
        background-color: blue;
      }
    }
    SCSS
    
    assert_file 'test.css', 'text/css', <<~CSS
    body {
      background-color: green; }
      body:hover {
        background-color: blue; }
    CSS
  end
  
end
