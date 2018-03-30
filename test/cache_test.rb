require 'test_helper'

class CacheTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.cache = Condenser::Cache::MemoryStore.new
  end
  
  test 'resolving and asset twice only compiles once' do
    file 'test.txt.erb', "1<%= 1 + 1 %>3\n"
    
    assert_file 'test.txt', 'text/plain', <<~CSS
    123
    CSS
    
    Condenser::Erubi.stubs(:call).never

    assert_file 'test.txt', 'text/plain', <<~CSS
    123
    CSS
  end

end
