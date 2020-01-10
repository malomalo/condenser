# frozen_string_literal: true
class Condenser::Cache
  class FileStore < Condenser::CacheStore
    GITKEEP_FILES = ['.gitkeep', '.keep'].freeze

    # Public: Initialize the cache store.
    #
    # root     - A String path to a directory to persist cached values to.
    # size     - A Integer of the maximum size the store will hold (in bytes).
    #            (default: 25MB).
    # logger   - The logger to which some info will be printed.
    #            (default logger level is FATAL and won't output anything).
    def initialize(root, size: 26_214_400, logger: nil)
      @root     = root
      @max_size = size
      @gc_size  = size * 0.75
      @logger   = logger
    end

    def get(key)
      path = File.join(@root, "#{key}.cache")
      
      value = safe_open(path) do |f|
        begin
          unmarshaled_deflated(f.read, Zlib::MAX_WBITS)
        rescue Exception => e
          # @logger.error do
            puts "#{self.class}[#{path}] could not be unmarshaled: #{e.class}: #{e.message}"
          # end
          nil
        end
      end

      FileUtils.touch(path) if value
      
      value
    end

    def set(key, value)
      path = File.join(@root, "#{key}.cache")
      
      # Ensure directory exists
      FileUtils.mkdir_p File.dirname(path)
      
      # Check if cache exists before writing
      exists = File.exist?(path)

      # Serialize value
      marshaled = Marshal.dump(value)

      # Compress if larger than 4KB
      if marshaled.bytesize > 4_096
        deflater = Zlib::Deflate.new(
          Zlib::BEST_COMPRESSION,
          Zlib::MAX_WBITS,
          Zlib::MAX_MEM_LEVEL,
          Zlib::DEFAULT_STRATEGY
        )
        deflater << marshaled
        raw = deflater.finish
      else
        raw = marshaled
      end

      # Write data
      Condenser::Utils.atomic_write(path) do |f|
        f.write(raw)
        @size = size + f.size unless exists
      end

      # GC if necessary
      gc! if size > @max_size

      value
    end
    
    # Public: Pretty inspect
    #
    # Returns String.
    def inspect
      "#<#{self.class}>"
    end

    # Public: Clear the cache
    #
    # adapted from ActiveSupport::Cache::FileStore#clear
    #
    # Deletes all items from the cache. In this case it deletes all the entries in the specified
    # file store directory except for .keep or .gitkeep. Be careful which directory is specified
    # as @root because everything in that directory will be deleted.
    #
    # Returns true
    def clear(options=nil)
      Dir.children(@root).each do |f|
        next if GITKEEP_FILES.include?(f)
        FileUtils.rm_r(File.join(@root, f))
      end
      true
    end
    
    def size
      @size ||= find_caches.inject(0) { |sum, (_, stat)| sum + stat.size }
    end
    
    private

    def safe_open(path, &block)
      File.open(path, 'rb', &block) if File.exist?(path)
    rescue Errno::ENOENT
    end
    
    # Returns an Array of [String filename, File::Stat] pairs sorted by
    # mtime.
    def find_caches
      Dir.glob(File.join(@root, '**/*.cache')).reduce([]) { |stats, filename|
        stat = safe_stat(filename)
        # stat maybe nil if file was removed between the time we called
        # dir.glob and the next stat
        stats << [filename, stat] if stat
        stats
      }.sort_by { |_, stat| stat.mtime.to_i }
    end
    
    def safe_stat(fn)
      File.stat(fn)
    rescue Errno::ENOENT
      nil
    end

    def gc!
      start_time = Time.now

      caches = find_caches
      size = caches.inject(0) { |sum, (_, stat)| sum + stat.size }

      delete_caches, keep_caches = caches.partition { |filename, stat|
        deleted = size > @gc_size
        size -= stat.size
        deleted
      }

      return if delete_caches.empty?

      FileUtils.remove(delete_caches.map(&:first), force: true)
      @size = keep_caches.inject(0) { |sum, (_, stat)| sum + stat.size }

      @logger.warn do
        secs = Time.now.to_f - start_time.to_f
        "#{self.class}[#{@root}] garbage collected " +
          "#{delete_caches.size} files (#{(secs * 1000).to_i}ms)"
      end
    end

    # Internal: Unmarshal optionally deflated data.
    #
    # Checks leading marshal header to see if the bytes are uncompressed
    # otherwise inflate the data an unmarshal.
    #
    # str - Marshaled String
    # window_bits - Integer deflate window size. See ZLib::Inflate.new()
    #
    # Returns unmarshaled Object or raises an Exception.
    def unmarshaled_deflated(str, window_bits = -Zlib::MAX_WBITS)
      major, minor = str[0], str[1]
      if major && major.ord == Marshal::MAJOR_VERSION &&
          minor && minor.ord <= Marshal::MINOR_VERSION
        marshaled = str
      else
        begin
          marshaled = Zlib::Inflate.new(window_bits).inflate(str)
        rescue Zlib::DataError
          marshaled = str
        end
      end
      Marshal.load(marshaled)
    end
    
  end
end