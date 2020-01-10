require 'listen'

class Condenser
  class BuildCache
    
    attr_reader :semaphore
    
    def initialize(path)
      @path = path
      @semaphore = Mutex.new
      @polling   = Listen::Adapter.select == Listen::Adapter::Polling
      @map_cache = {}
      @lookup_cache = {}
      @process_dependencies = {}
      @export_dependencies = {}

      @listener = Listen.to(*path) do |modified, added, removed|
        @semaphore.synchronize do
          added = added.reduce([]) do |rt, added_file|
            rt << added_file.match(/([^\.]+)(\.|$)/).to_a[1]
            if path_match = @path.find { |p| added_file.start_with?(p) }
              a = added_file.delete_prefix(path_match).match(/([^\.]+)(\.|$)/).to_a[1]
              b = (File.dirname(a) + "/*")
              
              rt << a << a.delete_prefix('/')
              rt << a << b.delete_prefix('/')
            end
          end
          
          removed.each do |file|
            @map_cache&.delete_if do |k,v|
              v.source_file == file
            end
            
            @process_dependencies[file]&.delete_if do |asset|
              asset.source_file == file
            end
            
            @export_dependencies[file]&.delete_if do |asset|
              asset.source_file == file
            end
          end

          @lookup_cache.delete_if do |key, value|
            if added.any?{ |a| key.starts_with?(a) }
              value.each do |asset|
                modified << asset.source_file
              end
              true
            end
          end
          @map_cache&.delete_if do |k,v|
            added.any?{ |a| k.starts_with?(a) }
          end
          
          modified.each do |file|
            @process_dependencies[file]&.each do |asset|
              asset.needs_reprocessing!
            end
            
            @export_dependencies[file]&.each do |asset|
              asset.needs_reexporting!
            end
          end
          
        end
      end
      @listener.start
    end
    
    def map(key)
      @map_cache[key] ||= yield
    end
    
    def []=(value, assets)
      @lookup_cache[value] = assets

      assets.each do |asset|
        asset.all_process_dependencies.each do |pd|
          @process_dependencies[pd] ||= Set.new
          @process_dependencies[pd] << asset
        end

        asset.all_export_dependencies.each do |pd|
          @export_dependencies[pd] ||= Set.new
          @export_dependencies[pd] << asset
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
        self[key] = value
      end
      
      value
    end
    
  end
end