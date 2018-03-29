# frozen_string_literal: true
module Condenser
  class Cache
    # Public: Basic in memory LRU cache.
    #
    # Assign the instance to the Environment#cache.
    #
    #     environment.cache = Sprockets::Cache::MemoryStore.new(1000)
    #
    # See Also
    #
    #   ActiveSupport::Cache::MemoryStore
    #
    class MemoryStore
      # Internal: Default key limit for store.
      DEFAULT_MAX_SIZE = 33_554_432 # 32 Megabytes
      PER_ENTRY_OVERHEAD = 240

      def initialize(options = {})
        @max_size = options[:size] || DEFAULT_MAX_SIZE
        @cache = {}
        @key_access = {}
        @cache_size = 0
      end

      def clear
        @cache.clear
        @key_access.clear
        @cache_size = 0
      end
      
      def fetch(key)
        value = get(key)
        
        if value.nil?
          value = yield
          set(key, value)
        end
        value
      end
      
      def get(key)
        value = @cache[key]
        @key_access[key] = Time.now.to_f if value
        value
      end

      def cached_size(key, value)
        key.to_s.bytesize + value.bytesize + PER_ENTRY_OVERHEAD
      end
      
      def set(key, value)
        if old_value = @cache[key]
          @cache_size -= (old_value.bytesize - value.bytesize)
        else
          @cache_size += cached_size(key, value)
        end
        @cache[key] = value
        @key_access[key] = Time.now.to_f
        prune if @cache_size > @max_size
        value
      end
      
      def delete(key)
        @key_access.delete(key)
        if value = @cache.delete(key)
          @cache_size -= cached_size(key, value)
          true
        else
          false
        end
      end
      
      def prune
        keys = @key_access.keys.sort { |a, b| @key_access[a].to_f <=> @key_access[b].to_f }
        keys.each do |key|
          delete(key)
          return if @cache_size <= @max_size
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
end
