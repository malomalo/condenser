# frozen_string_literal: true

class Condenser::Cache
  # Public: Basic in memory LRU cache. The default cache of a Condenser
  # environment.
  #
  #     environment.cache = Condenser::Cache::MemoryStore.new(size: 64 * 1024 * 1024)
  #
  # size - The maximum size of the store, in bytes (default: 32MB). Each entry
  #        counts its key, its value and PER_ENTRY_OVERHEAD bytes. The least
  #        recently read or written entries are evicted to stay under it.
  #
  class MemoryStore < Condenser::CacheStore
    # Internal: Default size limit for the store, in bytes.
    DEFAULT_MAX_SIZE = 33_554_432 # 32 Megabytes
    PER_ENTRY_OVERHEAD = 240

    def initialize(options = {})
      @max_size = options[:size] || DEFAULT_MAX_SIZE
      @cache = {}
      @cache_size = 0
    end

    def clear
      @cache.clear
      @cache_size = 0
    end
    
    def get(key)
      value = @cache.delete(key)
      @cache[key] = value unless value.nil?
      value
    end

    def cached_size(key, value)
      key.to_s.bytesize + value.bytesize + PER_ENTRY_OVERHEAD
    end
    
    def set(key, value)
      if old_value = @cache.delete(key)
        @cache_size -= cached_size(key, old_value)
      end
      @cache[key] = value
      @cache_size += cached_size(key, value)
      prune if @cache_size > @max_size
      value
    end
    
    def delete(key)
      if value = @cache.delete(key)
        @cache_size -= cached_size(key, value)
        true
      else
        false
      end
    end

    def prune
      while @cache_size > @max_size && (entry = @cache.first)
        delete(entry[0])
      end
    end

    # Public: Pretty inspect
    #
    # Returns String.
    def inspect
      "#<#{self.class} size=#{@cache_size}/#{@max_size}>"
    end

  end
end