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
  
  test 'scss import globing' do
    file "dir/a.scss", "body { color: blue; }"
    file "dir/b.scss", "body { color: green; }"
    
    file 'test.scss', '@import "dir/*"'
    
    assert_file 'test.css', 'text/css', <<~CSS
    body {
      color: blue; }
    
    body {
      color: green; }
    CSS
  end
  
end
