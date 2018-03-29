require 'digest/sha2'
require 'condenser/context'
require 'condenser/cache/null_store'

class Condenser
  module Environment
    
    attr_reader :root, :path, :cache
    
    def initialize(root)
      @path = []
      self.root = root
      @context_class = Class.new(Condenser::Context)
      @cache = Cache::NullStore.new
      super
    end

    def root=(path)
      @root = File.expand_path(path)
      append_path(@root)
    end

    def prepend_path(path)
      @path.unshift(File.expand_path(path, @root))
    end
  
    def append_path(path)
      @path.push(File.expand_path(path, @root))
    end
  
    def clear_path
      @path.clear
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