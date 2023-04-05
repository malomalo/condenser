# Transformer engine class for the SASS/SCSS compiler. Depends on the `sass`
# gem.
#
# For more infomation see:
#
#   https://github.com/sass/sass
#   https://github.com/rails/sass-rails
#
class Condenser::SassTransformer

  attr_accessor :options
  
  # Internal: Defines default sass syntax to use. Exposed so the ScssProcessor
  # may override it.
  def self.syntax
    :sass
  end

  def self.setup(environment)
    require "sassc" unless defined?(::SassC::Engine)
  end
  
  # Public: Return singleton instance with default options.
  #
  # Returns SassProcessor object.
  def self.instance
    @instance ||= new
  end

  def self.call(environment, input)
    instance.call(environment, input)
  end

  def self.cache_key
    instance.cache_key
  end

  attr_reader :cache_key

  def name
    self.class.name
  end
  
  # Public: Initialize template with custom options.
  #
  # options - Hash
  # cache_version - String custom cache version. Used to force a cache
  #                 change after code changes are made to Sass Functions.
  #
  def initialize(options = {}, &block)
    @options = options
    @cache_version = options[:cache_version]
    # @cache_key = "#{self.class.name}:#{VERSION}:#{Autoload::Sass::VERSION}:#{@cache_version}".freeze
    @importer_class = options[:importer] || Condenser::Sass::Importer
    
    @sass_config = options[:sass_config] || {}
    @functions = Module.new do
      include Functions
      include options[:functions] if options[:functions]
      class_eval(&block) if block_given?
    end
  end

  def call(environment, input)
    context = environment.new_context_class
    engine_options = merge_options({
      syntax:       self.class.syntax,
      filename:     input[:filename],
      source_map_file: "#{input[:filename]}.map",
      source_map_contents: true,
      # cache_store:  Cache.new(environment.cache),
      load_paths:   environment.path,
      importer:     @importer_class,
      condenser: { context: context, environment: environment },
      asset: input
    })
    
    engine = SassC::Engine.new(input[:source], engine_options)

    css = Condenser::Utils.module_include(SassC::Script::Functions, @functions) do
      engine.render
    end
    css.delete_suffix!("\n/*# sourceMappingURL=#{File.basename(input[:filename])}.map */")
    # engine.source_map
    # css = css.delete_suffix!("\n/*# sourceMappingURL= */\n")
    
    input[:source] = css
    # input[:map] = map.to_json({})
    input[:linked_assets]         += context.links
    input[:process_dependencies]  += context.dependencies
  end

  private

  # Public: Build the cache store to be used by the Sass engine.
  #
  # input - the input hash.
  # version - the cache version.
  #
  # Override this method if you need to use a different cache than the
  # Condenser cache.
  def build_cache_store(input, version)
    CacheStore.new(input[:cache], version)
  end

  def merge_options(options)
    defaults = @sass_config.dup

    if load_paths = defaults.delete(:load_paths)
      options[:load_paths] += load_paths
    end

    options.merge!(defaults)
    options
  end

  # Functions injected into Sass context during Condenser evaluation.
  module Functions
    include Condenser::Sass::Functions

    # Returns a Sass::Script::String.
    def asset_path(path, options = {})
      condenser_context.link_asset(path.value)

      path = condenser_context.asset_path(path.value, options)
      query    = "?#{query}" if query
      fragment = "##{fragment}" if fragment
      SassC::Script::Value::String.new("#{path}#{query}#{fragment}", :string)
    end

    # Returns a Sass::Script::String.
    def asset_url(path, options = {})
      SassC::Script::Value::String.new("url(#{asset_path(path, options).value})")
    end

    protected

    def condenser_context
      options[:condenser][:context]
    end
    
    def condenser_environment
      options[:condenser][:environment]
    end
  end
end

class Condenser::ScssTransformer < Condenser::SassTransformer
  def self.syntax
    :scss
  end
end
