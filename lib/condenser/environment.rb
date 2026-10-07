# frozen_string_literal: true

require 'digest/sha2'
require 'condenser/context'
require 'condenser/cache_store'
require 'condenser/cache/null_store'
require 'condenser/cache/memory_store'
require 'condenser/cache/file_store'

class Condenser
  module Environment
    
    attr_reader :path, :npm_path
    attr_accessor :cache
    
    def initialize(*args, **kws, &block)
      @loaded_processors = Set.new
      @context_class = Class.new(Condenser::Context)
      super
    end
    
    def load_processors(*processors)
      processors.flatten!
      loading = Set.new(processors) - @loaded_processors
      loading.each do |processor|
        processor.setup(self)
        @loaded_processors << processor
      end
      remember_loaded_processors if !loading.empty?
    end

    # Processors are set up the first time an asset uses them, and some
    # setups change how assets resolve (e.g. EJX adds its asset directory to
    # the load path). On a warm build an asset's cache key can be computed
    # before any asset that uses such a processor is processed, so set up the
    # processors earlier builds with this pipeline used before anything is
    # looked up.
    def load_previously_used_processors
      return if @previously_used_processors_loaded
      @previously_used_processors_loaded = true

      names = cache.get(loaded_processors_cache_key)
      load_processors(Marshal.load(names).filter_map(&:safe_constantize)) if names
    end

    def prepend_path(*paths)
      paths.flatten.each do |path|
        path = File.expand_path(path)
        raise ArgumentError, "Path \"#{path}\" does not exists" if !File.directory?(path)
        @path.unshift(path)
      end
      load_path_changed!
    end
  
    def append_path(*paths)
      paths.flatten.each do |path|
        path = File.expand_path(path)
        raise ArgumentError, "Path \"#{path}\" does not exists" if !File.directory?(path)
        @path.push(path)
      end
      load_path_changed!
    end

    def npm_path=(path)
      if path.nil?
        @npm_path = nil
      else
        path = File.expand_path(path)
        raise ArgumentError, "Path \"#{path}\" does not exists" if !File.directory?(path)
        @npm_path = path
      end
      load_path_changed!
    end
  
    def append_npm_path(*paths)
      paths.flatten.each do |path|
        self.npm_path = path
      end
    end
  
    def clear_path
      @path.clear
      load_path_changed!
    end
    
    # Every cached lookup depends on the load paths, including lookups that
    # found nothing, so they have to be redone when the paths change.
    def load_path_changed!
      build_cache.clear_lookups if instance_variable_defined?(:@build_cache)
    end
    
    def new_context_class
      context_class.new(self)
    end
    
    # This class maybe mutated and mixed in with custom helpers.
    #
    #     environment.context_class.instance_eval do
    #       include MyHelpers
    #       def asset_url; end
    #     end
    #
    attr_reader :context_class

    private

    def loaded_processors_cache_key
      "loaded-processors/#{pipline_digest}"
    end

    def remember_loaded_processors
      key = loaded_processors_cache_key
      names = (cached = cache.get(key)) ? Marshal.load(cached) : []
      loaded = @loaded_processors.filter_map(&:name)
      cache.set(key, Marshal.dump((names | loaded).sort)) if !(loaded - names).empty?
    end
  end
end