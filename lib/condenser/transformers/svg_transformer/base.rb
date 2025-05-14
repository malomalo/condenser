# frozen_string_literal: true

class Condenser::SVGTransformer::Base
  
  attr_accessor :children

  def initialize(escape: nil)
    @children = []
  end

  def to_module()
    var_generator = Condenser::SVGTransformer::VarGenerator.new

    <<~JS
      export default function (svgAttributes) {
      #{@children.last.to_js(var_generator: var_generator)}
          if (svgAttributes) {
              Object.keys(svgAttributes).forEach(function (key) {
                  __a.setAttribute(key, svgAttributes[key]);
              });
          }

          return __a;
      }
    JS
  end

end
