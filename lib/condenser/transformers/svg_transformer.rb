# frozen_string_literal: true

class Condenser::SVGTransformer
  
  autoload :Base, File.expand_path('../svg_transformer/base', __FILE__)
  autoload :Tag, File.expand_path('../svg_transformer/tag', __FILE__)
  autoload :Template, File.expand_path('../svg_transformer/template', __FILE__)
  autoload :TemplateError, File.expand_path('../svg_transformer/template_error', __FILE__)
  autoload :Value, File.expand_path('../svg_transformer/value', __FILE__)
  autoload :VarGenerator, File.expand_path('../svg_transformer/var_generator', __FILE__)
  
  def self.setup(env)
  end

  def self.call(environment, input)
    input[:source] = Condenser::SVGTransformer::Template.new(input[:source]).to_module
  end

end


