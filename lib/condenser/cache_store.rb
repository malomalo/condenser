# frozen_string_literal: true

class Condenser::CacheStore

  # With +force+ the block is run even if the key exists, and its result is
  # stored if it differs from the cached value.
  def fetch(key, force: false)
    cached = get(key)
    return Marshal.load(cached) if !cached.nil? && !force

    value = yield
    dumped = Marshal.dump(value)
    set(key, dumped) if cached != dumped
    value
  end
  
  # Try to fetch key_or_proc if key exists.
  #
  # If the key exist it will fetch key_or_proc from the cache
  #
  # Otherwise run the block and store results under key_or_proc, which is
  # evaluated after the block so it can depend on what the block changed.
  def fetch_if(key_or_proc, key, &block)
    if get(key)
      cached = get(key_or_proc.is_a?(Proc) ? key_or_proc.call : key_or_proc)
      return Marshal.load(cached) if !cached.nil?
    end

    value = block.call
    key_or_proc = key_or_proc.call if key_or_proc.is_a?(Proc)
    set(key_or_proc, Marshal.dump(value))
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