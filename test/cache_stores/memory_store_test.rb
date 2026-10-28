require 'test_helper'

class CacheMemoryStoreTest < ActiveSupport::TestCase

  ENTRY = Condenser::Cache::MemoryStore::PER_ENTRY_OVERHEAD

  def entry_size(key, value)
    key.bytesize + value.bytesize + ENTRY
  end

  def assert_cache_size(expected, store)
    assert_match(/ size=#{expected}\//, store.inspect)
  end

  test 'prune evicts the least recently used keys first' do
    store = Condenser::Cache::MemoryStore.new(size: entry_size('a', 'x') * 3)
    store.set('a', 'x')
    store.set('b', 'x')
    store.set('c', 'x')

    assert_equal 'x', store.get('a')
    store.set('d', 'x')

    assert_nil store.get('b')
    assert_equal 'x', store.get('a')
    assert_equal 'x', store.get('c')
    assert_equal 'x', store.get('d')

    store.set('c', 'y')
    store.set('e', 'x')
    assert_nil store.get('a')
    assert_equal 'y', store.get('c')
  end

  test 'prune evicts until the store is under its size' do
    store = Condenser::Cache::MemoryStore.new(size: entry_size('a', 'x') * 3)
    %w[a b c].each { |k| store.set(k, 'x') }
    store.set('d', 'x' * (ENTRY + 2))

    assert_nil store.get('a')
    assert_nil store.get('b')
    assert_equal 'x', store.get('c')
    assert_cache_size entry_size('c', 'x') + entry_size('d', 'x' * (ENTRY + 2)), store
  end

  test 'size stays correct across overwrites, deletes, prunes and clear' do
    store = Condenser::Cache::MemoryStore.new(size: 10_000)
    assert_cache_size 0, store

    store.set('a', 'xx')
    store.set('b', 'yyyy')
    assert_cache_size entry_size('a', 'xx') + entry_size('b', 'yyyy'), store

    store.set('a', 'xxxxxx')
    assert_cache_size entry_size('a', 'xxxxxx') + entry_size('b', 'yyyy'), store

    store.set('a', 'x')
    assert_cache_size entry_size('a', 'x') + entry_size('b', 'yyyy'), store

    assert_equal true, store.delete('b')
    assert_cache_size entry_size('a', 'x'), store
    assert_equal false, store.delete('b')
    assert_cache_size entry_size('a', 'x'), store

    store.set('big', 'z' * 10_000)
    assert_nil store.get('a')
    assert_nil store.get('big')
    assert_cache_size 0, store

    store.set('a', 'x')
    store.clear
    assert_nil store.get('a')
    assert_cache_size 0, store
  end

  test 'inspect' do
    assert_equal '#<Condenser::Cache::MemoryStore size=0/1024>', Condenser::Cache::MemoryStore.new(size: 1024).inspect
  end

end
