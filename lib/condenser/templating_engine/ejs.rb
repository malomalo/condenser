# frozen_string_literal: true

class Condenser::EjsTemplate < Condenser::Processor

  def setup(environment)
    require 'ejs' unless defined?(::EJS)

    if !environment.path.include?(EJS::ASSET_DIR)
      environment.append_path(EJS::ASSET_DIR)
    end
  end
  
  def call(environment, input)
    input[:source] = ::EJS.transform(input[:source], {strict: true})
  end

end