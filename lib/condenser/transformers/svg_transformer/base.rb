class Condenser::SVGTransformer::Base
  
  attr_accessor :children

  def initialize(escape: nil)
    @children = []
  end

  def to_module()
    var_generator = Condenser::SVGTransformer::VarGenerator.new

    <<~JS
      export default function () {
      #{@children.last.to_js(var_generator: var_generator)}
      }
    JS
  end

end
