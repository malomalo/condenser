# frozen_string_literal: true

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
    context = environment.new_context_class(source_file: data[:source_file], content_type: data[:content_type].last)
    source = context.instance_eval(&source)

    data[:source] = source
    data[:linked_assets].merge(context.links)
    data[:process_dependencies].merge(context.dependencies)
    data[:file_dependencies].merge(context.file_dependencies)
    data[:directory_dependencies].merge(context.directory_dependencies)
  end

end