require 'test_helper'

class CondenserErubiTest < ActiveSupport::TestCase

  test 'find' do
    file 'test.js.erb', "1<%= 1 + 1 %>3\n"
    
    assert_file 'test.js', 'application/javascript', <<~CSS
    123
    CSS
  end
  
end
