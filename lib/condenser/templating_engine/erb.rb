require "erubi"

class Condenser
  class Erubi
    
    def self.call(asset)
      source = ::Erubi::Engine.new(asset.source).src
      # source = eval(source, input[:context], input[:filename] || "(erubi)")
      source = eval(source, nil, asset.filename || "(erubi)")

      asset.source = source
    end
    
  end
end