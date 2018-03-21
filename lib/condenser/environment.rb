require 'digest/sha2'

class Condenser
  module Environment
    
    attr_reader :root, :path
    
    def initialize(root)
      @path = []
      self.root = root
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
    
  end
end