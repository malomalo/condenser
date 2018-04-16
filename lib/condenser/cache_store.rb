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