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
    file "c/dir/a.scss", "body { color: blue; }"
    file "c/dir/b.scss", "body { color: green; }"
    
    file 'c/test.scss', '@import "./dir/*"'
    
    assert_file 'c/test.css', 'text/css', <<~CSS
    body {
      color: blue; }
    
    body {
      color: green; }
    CSS
    
    file 'c/test2.scss', '@import "c/dir/*"'
    
    assert_file 'c/test2.css', 'text/css', <<~CSS
    body {
      color: blue; }
    
    body {
      color: green; }
    CSS
  end
  
end
