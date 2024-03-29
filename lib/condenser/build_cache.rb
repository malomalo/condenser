class Condenser
  class BuildCache
    
    attr_reader :semaphore, :listening, :logger
    
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
                @export_dependencies[v.source_file]&.each do |a| 
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
                  @export_dependencies[v.source_file]&.each do |a| 
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
              @process_dependencies[file]&.delete_if do |asset|
                if asset.source_file == file
                  true
                else
                  asset.needs_reprocessing!
                  false
                end
              end
            
              @export_dependencies[file]&.delete_if do |asset|
                if asset.source_file == file
                  true
                else
                  asset.needs_reexporting!
                  false
                end
              end
            end
            
            modified.each do |file|
              @process_dependencies[file]&.each do |asset|
                asset.needs_reprocessing!
              end
            
              @export_dependencies[file]&.each do |asset|
                asset.needs_reexporting!
              end
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
      
      if @fetching.nil?
        begin
          assets.each do |asset|
            @fetching = Set.new
            asset.all_process_dependencies(@fetching).each do |pd|
              @process_dependencies[pd] ||= Set.new
              @process_dependencies[pd] << asset
            end

            @fetching = Set.new
            asset.all_export_dependencies(@fetching).each do |pd|
              @export_dependencies[pd] ||= Set.new

              @export_dependencies[pd] << asset
            end
          end
        ensure
          @fetching = nil
        end
      end
    end
    
    def [](value)
      @lookup_cache[value]
    end
    
    def fetch(key)
      value = self[key]
      
      if value.nil?
        value = yield
        if (value.is_a?(Array) ? !value.empty? : value)
          self[key] = value
        end
      end
      
      value
    end
    
  end
end