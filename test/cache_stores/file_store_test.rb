require 'test_helper'

class CacheFileStoreTest < ActiveSupport::TestCase
  
  def setup
    super
    @cachepath = Dir.mktmpdir
    @env.cache = Condenser::Cache::FileStore.new(@cachepath)
  end
  
  def teardown
    super
    FileUtils.remove_entry(@cachepath, true)
  end

  test 'reading from a populated cache store' do
    file 'test.txt.erb', "1<%= 1 + 1 %>3\n"
    
    assert_file 'test.txt', 'text/plain', <<~CSS
    123
    CSS

    oldenv = @env
    begin
      @env = Condenser.new(@path)
      @env.cache = Condenser::Cache::FileStore.new(@cachepath)
      Condenser::Erubi.stubs(:call).never

      assert_file 'test.txt', 'text/plain', <<~CSS
      123
      CSS
    ensure
      @env = oldenv
    end
  end

end
