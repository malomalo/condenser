# frozen_string_literal: true

require 'digest'
require 'json'

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

  RESERVED_SASS_CONFIG = {
    syntax: 'use Condenser::SassTransformer or Condenser::ScssTransformer',
    url: "condenser sets it to the asset's",
    importer: 'use the `importer:` option',
    importers: 'use the `importer:` option',
    functions: 'use the `functions:` option or a block',
    logger: 'use the `logger:` option',
    load_paths: "add the paths to the environment's path, so imports are tracked as dependencies"
  }.freeze

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

  def self.options
    instance.options
  end

  def name
    self.class.name
  end

  # Public: Initialize template with custom options.
  #
  # cache_version - String custom cache version. Changing it changes the
  #                 cache key of every stylesheet. The source files that
  #                 define the `functions:` module's and the block's
  #                 methods are part of the cache key, so use this when the
  #                 functions depend on code defined elsewhere.
  # sass_config - Hash of options passed to Dart Sass, e.g. `style`,
  #               `silence_deprecations` or `quiet_deps`. The options
  #               condenser sets (see RESERVED_SASS_CONFIG) raise an
  #               ArgumentError.
  # functions - Module of additional functions (see Condenser::Sass::Functions).
  # importer - Class used to resolve imports (see Condenser::Sass::Importer).
  # logger - Sass logger for warnings and `@debug`. Defaults to sending them
  #          to the environment's logger (see Condenser::Sass::Logger).
  #
  def initialize(cache_version: nil, sass_config: {}, functions: nil, importer: Condenser::Sass::Importer, logger: nil, &block)
    Condenser::Sass.check_reserved_options!(sass_config, RESERVED_SASS_CONFIG, 'sass_config')
    function_module = Module.new do
      include Condenser::Sass::Functions
      include functions if functions
      class_eval(&block) if block_given?
    end
    # Only options that differ from the defaults, and the Dart Sass version,
    # since these are part of the pipeline digest
    @options = {
      cache_version: cache_version,
      sass_config: (sass_config unless sass_config.empty?),
      functions: functions_digest(function_module, block),
      importer: (importer unless importer == Condenser::Sass::Importer),
      dart_sass: Condenser::Sass.version
    }.compact
    @logger = logger
    @importer_class = importer

    @sass_config = sass_config
    @function_context = Class.new(FunctionContext) { include function_module }
    @function_names = function_module.public_instance_methods.reject { |m| m.end_with?('_signature') }
  end

  def call(environment, input)
    context = environment.new_context_class
    importer = @importer_class.new(environment, input)
    functions = @function_context.new(context: context, environment: environment, asset: input)

    result = ::Sass.compile_string(importer.source(self.class.syntax), **{
      syntax: self.class.syntax,
      url: importer.url,
      importer: importer,
      importers: [importer],
      functions: sass_functions(functions),
      logger: @logger || Condenser::Sass::Logger.new(environment.logger)
    }.merge(@sass_config))

    input[:source] = result.css
    input[:linked_assets]         += context.links
    input[:process_dependencies]  += context.dependencies
  rescue ::Sass::CompileError => e
    raise Condenser::Sass.compile_error(e, input[:filename])
  end

  private

  # A digest of the custom functions' names and the files they're defined
  # in, or nil if there are none. Condenser's own functions are left out.
  def functions_digest(function_module, block)
    methods = (function_module.instance_methods + function_module.private_instance_methods).map { |name| function_module.instance_method(name) }
    methods.reject! { |method| Condenser::Sass::Functions.ancestors.include?(method.owner) }
    return if methods.empty? && block.nil?

    files = methods.filter_map { |method| method.source_location&.first }
    files << block.source_location.first if block
    Digest::SHA256.hexdigest(JSON.generate([
      methods.map(&:name).sort,
      files.uniq.select { |file| File.file?(file) }.map { |file| Digest::SHA256.file(file).hexdigest }.sort
    ]))
  end

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
    when Array then ::Sass::Value::List.new(value.map { |v| to_sass_value(v) })
    when Hash then ::Sass::Value::Map.new(value.to_h { |k, v| [to_sass_value(k.is_a?(Symbol) ? k.to_s : k), to_sass_value(v)] })
    else ::Sass::Value::String.new(value.to_s, quoted: false)
    end
  end

  # The object the Sass functions are called on.
  class FunctionContext
    def initialize(context:, environment:, asset:)
      @context = context
      @environment = environment
      @asset = asset
    end
  end
end

class Condenser::ScssTransformer < Condenser::SassTransformer
  def self.syntax
    :scss
  end
end
