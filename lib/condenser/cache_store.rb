# frozen_string_literal: true
class Condenser::CacheStore

  def fetch(key)
    value = get(key)
    
    if value.nil?
      value = yield
      set(key, Marshal.dump(value))
    else
      value = Marshal.load(value)
    end
    value
  end
  
  # Try to fetch key_or_proc if key exists.
  #
  # If the key exist it will fetch key_or_proc from the cache
  #
  # If key does not exists run the block and store results under key_or_proc.
  def fetch_if(key_or_proc, key, &block)
    if get(key)
      key_or_proc = key_or_proc.call if key_or_proc.is_a?(Proc)
      value = fetch(key_or_proc, &block)
    else
      value = block.call
      key_or_proc = key_or_proc.call if key_or_proc.is_a?(Proc)
      set(key_or_proc, Marshal.dump(value))
    end
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

end