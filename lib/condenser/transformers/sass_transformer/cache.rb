class Condenser::SassTransformer
  # Internal: Cache wrapper for Sprockets cache adapter.
  class Cache < ::Sass::CacheStores::Base
    def initialize(cache)
      @cache = cache
    end

    def _store(key, version, sha, contents)
      @cache.set("#{version}/#{key}/#{sha}", contents)#, true
    end

    def _retrieve(key, version, sha)
      @cache.get("#{version}/#{key}/#{sha}")#, true
    end

    def path_to(key)
      key
    end
  end
end
