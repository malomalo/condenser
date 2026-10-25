# frozen_string_literal: true

require 'digest/sha2'
require 'condenser/context'
require 'condenser/cache_store'
require 'condenser/cache/null_store'
require 'condenser/cache/memory_store'
require 'condenser/cache/file_store'

class Condenser
  module Environment
    
    attr_reader :path, :npm_path, :watched_paths
    attr_accessor :cache
    
    def initialize(*args, **kws, &block)
      @loaded_processors = Set.new
      @watched_paths = []
      @context_class = Class.new(Condenser::Context)
      super
    end
    
    def load_processors(*processors)
      processors.flatten!
      (Set.new(processors) - @loaded_processors).each do |processor|
        processor.setup(self)
        @loaded_processors << processor
      end
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

    # Watches +paths+ for changes to file dependencies, without adding them to
    # the load path, so assets aren't resolved from them. +ignore+ lists
    # Regexps matched against the paths relative to each path, or directories
    # relative to it; node_modules, .git, tmp and log are always ignored. A
    # path that's already watched, as or under a watched path, is skipped.
    #
    #     env.watch(Rails.root, ignore: ['public/assets', 'storage'])
    def watch(*paths, ignore: [])
      paths.flatten.each do |path|
        path = File.expand_path(path)
        raise ArgumentError, "Path \"#{path}\" does not exists" if !File.directory?(path)
        real = BuildCache.real_path(path)
        next if @watched_paths.any? { |watched, watched_ignore|
          BuildCache.covers?(BuildCache.real_path(watched), real, ignore: watched_ignore)
        }

        @watched_paths << [path, ignore]
        build_cache.watch(path, ignore: ignore) if instance_variable_defined?(:@build_cache)
      end
    end

    # The default #inspect dumps every processor, cache and lookup.
    def inspect
      "#<#{self.class.name} paths=#{path.size} npm_path=#{npm_path.inspect} base=#{base.inspect}>"
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
      @dependency_paths&.clear
    end
    
    def new_context_class(source_file: nil, content_type: nil)
      context_class.new(self, source_file: source_file, content_type: content_type)
    end
    
    # This class maybe mutated and mixed in with custom helpers.
    #
    #     environment.context_class.instance_eval do
    #       include MyHelpers
    #       def asset_url; end
    #     end
    #
    attr_reader :context_class
  end
end