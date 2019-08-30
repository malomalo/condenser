class Condenser::SassMinifier
    
  def self.instance
    @instance ||= new
  end

  def self.call(environment, input)
    require "sass" unless defined?(::Sass::Engine)
    
    instance.call(environment, input)
  end
  
  def initialize(options = {})
    @options = options.merge({
      syntax: :scss,
      cache: false,
      read_cache: false,
      style: :compressed
    }).freeze
  end

  def call(environment, input)
    engine = Sass::Engine.new(input[:source], {filename: input[:filename]}.merge(@options))
    css, map = engine.render_with_sourcemap('')
    css = css.delete_suffix!("\n/*# sourceMappingURL= */\n")
    
    input[:source] = css
  end

end