# frozen_string_literal: true
class Condenser::Cache
  class NullStore

    def get(key)
      nil
    end

    def set(key, value)
      value
    end

    def fetch(key)
      value = get(key)
      
      if value.nil?
        value = yield
        set(key, value)
      end
      value
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