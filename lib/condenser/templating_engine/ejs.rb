class Condenser::EjsTemplare < Condenser::NodeProcessor

  def self.setup(environment)
    require 'ejs' unless defined?(::EJS)

    if !environment.path.include?(EJS::ASSET_DIR)
      environment.append_path(EJS::ASSET_DIR)
    end
  end
  
  def self.call(environment, input)
    new.call(environment, input)
  end

  def call(environment, input)
    input[:source] = ::EJS.transform(input[:source], {strict: true})
  end

end