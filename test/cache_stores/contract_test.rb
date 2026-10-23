require 'test_helper'

# The interface the rest of condenser calls on a cache, run over every store.
class CacheStoreContractTest < ActiveSupport::TestCase

  def setup
    super
    @cachepath = Dir.mktmpdir
  end

  def teardown
    super
    FileUtils.remove_entry(@cachepath, true)
  end

  def stores
    {
      Condenser::Cache::MemoryStore.new => true,
      Condenser::Cache::FileStore.new(@cachepath) => true,
      Condenser::Cache::NullStore.new => false
    }
  end

  test 'every store implements the cache interface' do
    stores.each_key do |store|
      %i[get set fetch fetch_if clear].each do |method|
        assert_respond_to store, method
      end
      assert_equal %i[key force], store.method(:fetch).parameters.map(&:last), store.inspect
      assert_equal %i[key_or_proc key block], store.method(:fetch_if).parameters.map(&:last), store.inspect
    end
  end

  test 'fetch runs the block only on a miss, unless forced' do
    stores.each do |store, caches|
      assert_equal 1, store.fetch('key') { 1 }
      assert_equal (caches ? 1 : 2), store.fetch('key') { 2 }, store.inspect
      assert_equal 3, store.fetch('key', force: true) { 3 }
    end
  end

  test 'fetch_if returns the cached value only once the dependency key is set' do
    stores.each do |store, caches|
      assert_equal 1, store.fetch_if(Proc.new { 'value' }, 'deps') { 1 }
      assert_equal 2, store.fetch_if(Proc.new { 'value' }, 'deps') { 2 }, store.inspect

      store.fetch('deps') { [] }
      assert_equal (caches ? 2 : 3), store.fetch_if(Proc.new { 'value' }, 'deps') { 3 }, store.inspect
      assert_equal (caches ? 2 : 4), store.fetch_if('value', 'deps') { 4 }, store.inspect

      assert_equal true, !!store.clear
      assert_equal 5, store.fetch_if('value', 'deps') { 5 }, store.inspect
    end
  end

end
