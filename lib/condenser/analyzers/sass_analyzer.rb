require 'sass'

class Condenser
  class SassAnalyzer

    # Internal: Defines default sass syntax to use. Exposed so the ScssProcessor
    # may override it.
    def self.syntax
      :sass
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

    def initialize(options = {})
      @sass_config = options[:sass_config] || {}
    end

    def call(environment, input)
      engine_options = merge_options({
        filename:     input[:filename],
        syntax:       self.class.syntax,
        cache_store:  SassTransformer::Cache.new(environment.cache),
      })

      engine = Sass::Engine.new(input[:source], engine_options)

      engine.to_tree.grep(Sass::Tree::ImportNode) do |n|
        next if n.imported_filename =~ /\Ahttps?:\/\//
        environment.resolve(n.imported_filename, input[:source_file]).each do |a|
          input[:dependencies] << a.filename
        end
      end
    end

    private

    def merge_options(options)
      defaults = @sass_config.dup

      if load_paths = defaults.delete(:load_paths)
        options[:load_paths] += load_paths
      end

      options.merge!(defaults)
      options
    end
  end

  class ScssAnalyzer < SassAnalyzer
    def self.syntax
      :scss
    end
  end
  
end
