class Condenser::Erubi

  def self.setup(environment)
    require "erubi" unless defined?(::Erubi::Engine)
  end

  def self.call(environment, data)
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