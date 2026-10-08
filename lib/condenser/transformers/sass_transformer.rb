# frozen_string_literal: true

# Transformer engine class for the SASS/SCSS compiler. Depends on the
# `sass-embedded` gem (Dart Sass).
#
# For more infomation see:
#
#   https://sass-lang.com/dart-sass/
#   https://github.com/sass-contrib/sass-embedded-host-ruby
#
class Condenser::SassTransformer

  attr_accessor :options

  # Internal: Defines default sass syntax to use. Exposed so the ScssProcessor
  # may override it.
  def self.syntax
    :indented
  end

  def self.setup(environment)
    Condenser::Sass.require_sass_embedded!(name)
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
  # sass_config - Hash of options passed to Dart Sass, e.g. `style`,
  #               `silence_deprecations` or `quiet_deps`.
  # functions - Module of additional functions (see Condenser::Sass::Functions).
  # importer - Class used to resolve imports (see Condenser::Sass::Importer).
  # logger - Sass logger for warnings and `@debug`. Defaults to sending them
  #          to the environment's logger (see Condenser::Sass::Logger).
  #
  def initialize(options = {}, &block)
    options = options.dup
    @logger = options.delete(:logger)
    @options = options
    @cache_version = options[:cache_version]
    @importer_class = options[:importer] || Condenser::Sass::Importer

    @sass_config = options[:sass_config] || {}
    functions = Module.new do
      include Functions
      include options[:functions] if options[:functions]
      class_eval(&block) if block_given?
    end
    @function_context = Class.new(FunctionContext) { include functions }
    @function_names = functions.public_instance_methods.reject { |m| m.end_with?('_signature') }
  end

  def call(environment, input)
    context = environment.new_context_class
    importer = @importer_class.new(environment, input)
    functions = @function_context.new(
      condenser: { context: context, environment: environment },
      asset: input
    )

    result = ::Sass.compile_string(input[:source], **{
      syntax: self.class.syntax,
      url: importer.url,
      importer: importer,
      importers: [importer],
      functions: sass_functions(functions),
      logger: @logger || Condenser::Sass::Logger.new(environment.logger)
    }.merge(Condenser::Sass.compile_options(@sass_config)))

    input[:source] = result.css
    input[:linked_assets]         += context.links
    input[:process_dependencies]  += context.dependencies
  end

  private

  def sass_functions(functions)
    @function_names.to_h do |name|
      method = functions.method(name)
      params = if functions.respond_to?(:"#{name}_signature")
        functions.public_send(:"#{name}_signature").keys
      else
        method.parameters.filter_map do |type, param|
          case type
          when :req then "$#{param}"
          when :opt then "$#{param}: null"
          end
        end
      end
      required = method.parameters.count { |type, _| type == :req }

      callback = lambda do |args|
        args = args.dup
        args.pop while args.size > required && args.last == ::Sass::Value::Null::NULL
        to_sass_value(method.call(*args))
      end
      ["#{name.to_s.tr('_', '-')}(#{params.join(', ')})", callback]
    end
  end

  def to_sass_value(value)
    case value
    when ::Sass::Value then value
    when nil then ::Sass::Value::Null::NULL
    when true then ::Sass::Value::Boolean::TRUE
    when false then ::Sass::Value::Boolean::FALSE
    when Numeric then ::Sass::Value::Number.new(value)
    else ::Sass::Value::String.new(value.to_s, quoted: false)
    end
  end

  # The object the Sass functions are called on.
  class FunctionContext
    attr_reader :options

    def initialize(options)
      @options = options
    end
  end

  # Functions injected into Sass context during Condenser evaluation.
  module Functions
    include Condenser::Sass::Functions
  end
end

class Condenser::ScssTransformer < Condenser::SassTransformer
  def self.syntax
    :scss
  end
end
