# frozen_string_literal: true

require 'json'

class Condenser::SVGTransformer::Value

  def initialize(value)
    @value = value
  end

  def to_js
    JSON.generate(@value)
  end
  
end