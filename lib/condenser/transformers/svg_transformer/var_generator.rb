class Condenser::SVGTransformer::VarGenerator
  def initialize
    @current = nil
  end
  
  def next
    @current = @current.nil? ? '__a' : @current.next
    @current
  end
end