# frozen_string_literal: true

class Condenser::Cache
  # Public: A cache store that stores nothing; every fetch runs its block.
  class NullStore < Condenser::CacheStore

    def get(key)
      nil
    end

    def set(key, value)
      value
    end

    # Nothing is ever cached, so always run the block.
    def fetch(key, force: false)
      yield
    end

    # The dependency key is never cached, so always run the block. The value
    # key isn't stored, so a key Proc is never called.
    def fetch_if(key_or_proc, key, &block)
      block.call
    end

    def delete(key)
      false
    end

    # Public: Pretty inspect
    #
    # Returns String.
    def inspect
      "#<#{self.class}>"
    end

    # Public: Simulate clearing the cache
    #
    # Returns true
    def clear(options=nil)
      true
    end
  end
end
