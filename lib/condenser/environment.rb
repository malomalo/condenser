require 'digest/sha2'
require 'condenser/context'
require 'condenser/cache/null_store'
require 'condenser/cache/memory_store'

class Condenser
  module Environment
    
    attr_reader :path
    attr_accessor :cache
    
    def initialize
      @context_class = Class.new(Condenser::Context)
      super
    end

    def prepend_path(*paths)
      paths.flatten.each do |path|
        path = File.expand_path(path)
        raise ArgumentError, "Path \"#{path}\" does not exists" if !File.directory?(path)
        @path.unshift(path)
      end
    end
  
    def append_path(*paths)
      paths.flatten.each do |path|
        path = File.expand_path(path)
        raise ArgumentError, "Path \"#{path}\" does not exists" if !File.directory?(path)
        @path.push(path)
      end
    end
  
    def clear_path
      @path.clear
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
  end
end