# frozen_string_literal: true

class Condenser
  class BuildCache
    
    attr_reader :semaphore, :listening, :logger

    # Files that change when npm packages are installed or updated.
    # node_modules/.package-lock.json is rewritten by every `npm install`.
    NPM_LOCKFILES = %w(
      node_modules/.package-lock.json
      package-lock.json
      yarn.lock
      pnpm-lock.yaml
      bun.lock
      bun.lockb
    ).freeze

    def initialize(path, logger:, listen: {})
      @logger = logger
      @path = path
      @map_cache = {}
      @lookup_cache = {}
      @process_dependencies = {}
      @export_dependencies = {}
      @listening = if listen
        require 'listen'
        Listen::Adapter.select != Listen::Adapter::Polling
      else
        false
      end
      
      if !@listening
        @polling = false
      else
        @semaphore = Mutex.new
        @listener = Listen.to(*path) do |modified, added, removed|
          modified = Set.new(modified)
          added = Set.new(added)
          removed = Set.new(removed)
          
          @semaphore.synchronize do
            @logger.debug { "build cache semaphore locked by #{Thread.current.object_id}" }
            @logger.debug do
              (
                removed.map { |f| "Asset removed: #{f}" } +
                added.map { |f| "Asset created: #{f}" } +
                modified.map { |f| "Asset updated: #{f}" }
              ).join("\n")
            end

            globs = []
            (added + removed + modified).each do |file|
              globs << file.match(/([^\.]+)(\.|$)/).to_a[1]
              if path_match = @path.find { |p| file.start_with?(p) }
                a = file.delete_prefix(path_match).match(/([^\.]+)(\.|$)/).to_a[1]
                b = File.join(File.dirname(a), "*")
              
                globs << a << a.delete_prefix('/')
                globs << b << b.delete_prefix('/')
              end
            end

            others = []
            @map_cache&.delete_if do |k,v|
              if globs.any?{ |a| k.starts_with?(a) }
                dependents(@export_dependencies, v.source_file).each do |a|
                  others << "/#{a.filename}".delete_suffix(File.extname(a.filename))
                end
                true
              else
                false
              end
            end
            @map_cache&.delete_if do |k,v|
              others.any?{ |a| k.starts_with?(a) || k.starts_with?("/" + a) }
            end
            
            others = []
            @lookup_cache.delete_if do |key, value|
              if globs.any?{ |a| key.starts_with?(a) }
                value.each do |v|
                  dependents(@export_dependencies, v.source_file).each do |a|
                    others << "/#{a.filename}".delete_suffix(File.extname(a.filename))
                  end
                end
                value.each do |asset|
                  modified << asset.source_file
                end
                true
              end
            end
            @lookup_cache&.delete_if do |k,v|
              others.any?{ |a| k.starts_with?(a) || k.starts_with?("/" + a) }
            end
            

            
            removed.each do |file|
              dependents(@process_dependencies, file).each do |asset|
                asset.needs_reprocessing! if asset.source_file != file
              end
              dependents(@export_dependencies, file).each do |asset|
                asset.needs_reexporting! if asset.source_file != file
              end
              @process_dependencies[file]&.delete_if { |asset| asset.source_file == file }
              @export_dependencies[file]&.delete_if { |asset| asset.source_file == file }
            end
            
            modified.each do |file|
              dependents(@process_dependencies, file).each(&:needs_reprocessing!)
              dependents(@export_dependencies, file).each(&:needs_reexporting!)
            end

            @logger.debug { "build cache semaphore unlocked by #{Thread.current.object_id}" }
          end
        end
        @listener.start
      end
    end
    
    def map(key)
      @map_cache[key] ||= yield
    end
    
    def []=(value, assets)
      @lookup_cache[value] = assets
    end
    
    # Record the direct dependencies of an asset so the listener can find
    # everything that needs to be rebuilt when a file changes. Only direct
    # edges are stored; the transitive set is computed in #dependents when a
    # file actually changes.
    def record_process_dependencies(asset, deps)
      record_dependencies(@process_dependencies, asset, deps)
    end
    
    def record_export_dependencies(asset, deps)
      record_dependencies(@export_dependencies, asset, deps)
    end
    
    # Returns the assets that depend on +source_file+, either directly or
    # through other assets, including the assets built from +source_file+.
    def dependents(index, source_file)
      found = Set.new
      queue = [source_file]
      seen = Set.new
      while file = queue.shift
        next unless seen.add?(file)
        index[file]&.each do |asset|
          queue << asset.source_file if found.add?(asset)
        end
      end
      found
    end
    
    # node_modules isn't watched by the listener, so clear everything when
    # the npm packages change (e.g. after an `npm install`) instead.
    def clear_if_npm_changed(npm_path)
      return if npm_path.nil?

      fingerprint = NPM_LOCKFILES.filter_map do |lockfile|
        stat = File.stat(File.join(npm_path, lockfile))
        [lockfile, stat.mtime.to_f, stat.size]
      rescue Errno::ENOENT
        nil
      end

      if @npm_fingerprint && @npm_fingerprint != fingerprint
        @logger.info { "npm packages changed, clearing the build cache" }
        clear
      end
      @npm_fingerprint = fingerprint
    end

    def clear
      @map_cache.clear
      @lookup_cache.clear
      @process_dependencies.clear
      @export_dependencies.clear
    end

    def [](value)
      @lookup_cache[value]
    end
    
    def fetch(key)
      value = self[key]
      
      if value.nil?
        value = yield
        # Lookups that find nothing are only cached while listening, since
        # the listener is what clears them when a matching file is added.
        if @listening || (value.is_a?(Array) ? !value.empty? : value)
          self[key] = value
        end
      end
      
      value
    end
    
    private
    
    def record_dependencies(index, asset, deps)
      return if !@listening

      # An asset always depends on its own source file
      (@process_dependencies[asset.source_file] ||= Set.new) << asset
      (@export_dependencies[asset.source_file] ||= Set.new) << asset
      deps.each do |dep|
        (index[dep.source_file] ||= Set.new) << asset
      end
    end
    
  end
end