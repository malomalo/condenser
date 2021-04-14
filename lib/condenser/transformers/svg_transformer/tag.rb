class Condenser::SVGTransformer::Tag

  attr_accessor :tag_name, :attrs, :children, :namespace

  def initialize(name)
    @tag_name = name
    @attrs = []
    @children = []
  end

  def to_s
    @value
  end

  def inspect
    "#<SVG::Tag:#{self.object_id} @tag_name=#{tag_name}>"
  end

  def to_js(append: nil, var_generator:, indentation: 4, namespace: nil)
    namespace ||= self.namespace
    
    output_var = var_generator.next
    js = "#{' '*indentation}var #{output_var} = document.createElement"
    js << if namespace
      "NS(#{namespace.to_js}, #{JSON.generate(tag_name)});\n"
    else
      "(#{JSON.generate(tag_name)});\n"
    end

    @attrs.each do |attr|
      if attr.is_a?(Hash)
        attr.each do |k, v|
          js << "#{' '*indentation}#{output_var}.setAttribute(#{JSON.generate(k)}, #{v.is_a?(String) ? v : v.to_js});\n"
        end
      else
        js << "#{' '*indentation}#{output_var}.setAttribute(#{JSON.generate(attr)}, \"\");\n"
      end
    end

    @children.each do |child|
      js << if child.is_a?(Condenser::SVGTransformer::Tag)
        child.to_js(var_generator: var_generator, indentation: indentation, append: output_var, namespace: namespace)
      else
        child.to_js(var_generator: var_generator, indentation: indentation, append: output_var)
      end
    end

    js << if append
      "#{' '*indentation}#{append}.append(#{output_var});\n"
    else
      "#{' '*indentation}return #{output_var};"
    end
    js
  end
  
end

