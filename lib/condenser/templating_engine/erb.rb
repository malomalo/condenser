require "erubi"

class Condenser
  class Erubi
    
    def self.call(asset)
      source = ::Erubi::Engine.new(asset.source, {
        preamble:   "@output_buffer = String.new;",#output_buffer || String.new;",
        bufvar:     "@output_buffer",
        postamble:  "@output_buffer.to_s"
      }).src
      
      # source = eval(source, input[:context], input[:filename] || "(erubi)")
      source = eval("proc { #{source} }", nil, asset.filename || "(erubi)")
      source = asset.new_context_class.instance_eval(&source)
      # source = eval()

      asset.source = source
    end
    
  end
end