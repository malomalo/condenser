class Condenser::Erubi

  def self.call(environment, data)
    require "erubi" unless defined?(::Erubi::Engine)
      
    source = ::Erubi::Engine.new(data[:source], {
      preamble:   "@output_buffer = String.new;",
      bufvar:     "@output_buffer",
      postamble:  "@output_buffer.to_s"
    }).src
    
    source = eval("proc { #{source} }", nil, data[:filename] || "(erubi)")
    source = environment.new_context_class.instance_eval(&source)

    data[:source] = source
  end

end