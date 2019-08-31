class Condenser::SassMinifier
    
  def self.instance
    @instance ||= new
  end

  def self.call(environment, input)
    require "sassc" unless defined?(::SassC::Engine)
    
    instance.call(environment, input)
  end
  
  def initialize(options = {})
    @options = {
      syntax:     :scss,
      cache:      false,
      read_cache: false,
      style:      :compressed
    }.merge(options).freeze
  end

  def call(environment, input)
    engine = SassC::Engine.new(input[:source], {
      filename: input[:filename],
      source_map_file: "#{input[:filename]}.map",
      source_map_contents: true
    }.merge(@options))
    
    css = engine.render
    css.delete_suffix!("\n/*# sourceMappingURL=#{File.basename(input[:filename])}.map */")
    # engine.source_map
    
    input[:source] = css
  end

end