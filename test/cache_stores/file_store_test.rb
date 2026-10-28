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
      @env = Condenser.new(@path, base: @path)
      @env.cache = Condenser::Cache::FileStore.new(@cachepath)
      Condenser::Erubi.stubs(:call).never

      assert_file 'test.txt', 'text/plain', <<~CSS
      123
      CSS
    ensure
      @env = oldenv
    end
  end

  test 'fetch with force stores the new value only if it changed' do
    store = @env.cache
    assert_equal [1], store.fetch('key') { [1] }

    store.expects(:set).never
    assert_equal [1], store.fetch('key', force: true) { [1] }

    store.unstub(:set)
    assert_equal [2], store.fetch('key', force: true) { [2] }
    assert_equal [2], Condenser::Cache::FileStore.new(@cachepath).fetch('key') { [3] }
  end

  test 'delete removes the cached file and reports whether the key existed' do
    store = @env.cache
    store.set('key', 'value')
    path = File.join(@cachepath, 'key.cache')
    assert File.exist?(path)
    size_before = store.size
    file_size = File.size(path)

    assert_equal true, store.delete('key')
    assert_equal size_before - file_size, store.size
    assert_nil store.get('key')
    assert_not File.exist?(path)

    assert_equal false, store.delete('key')
  end

  test 'overwriting a key with a larger or smaller value updates the size' do
    store = @env.cache
    path = File.join(@cachepath, 'key.cache')
    assert_equal 0, store.size

    store.set('other', 'value')
    other_size = File.size(File.join(@cachepath, 'other.cache'))

    store.set('key', 'small')
    assert_equal other_size + File.size(path), store.size

    store.set('key', 'larger' * 100)
    assert_equal other_size + File.size(path), store.size

    store.set('key', 's')
    assert_equal other_size + File.size(path), store.size

    assert_equal store.size, Condenser::Cache::FileStore.new(@cachepath).size
  end

  test 'gc! runs when overwriting a key takes the store over its size' do
    store = Condenser::Cache::FileStore.new(@cachepath, size: 2_000)
    store.set('key', 'x' * 10)
    store.expects(:gc!).once
    store.set('key', 'x' * 3_000)
  end

end
