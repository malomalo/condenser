# frozen_string_literal: true

class Condenser::SassMinifier

  def self.setup(environment)
    Condenser::Sass.require_sass_embedded!(name)
  end

  def self.instance
    @instance ||= new
  end

  def self.call(environment, input)
    instance.call(environment, input)
  end

  def self.options
    instance.options
  end

  # The Dart Sass options and version, which are part of the export
  # pipeline digest.
  attr_reader :options

  # logger - Sass logger for warnings. Defaults to the environment's logger.
  # options - Options passed to Dart Sass, e.g. `style` (default :compressed).
  def initialize(logger: nil, **options)
    @logger = logger
    @sass_options = {
      style: :compressed
    }.merge(options).freeze
    @options = @sass_options.merge(dart_sass: Condenser::Sass.version).compact.freeze
  end

  def name
    self.class.name
  end

  def call(environment, input)
    self.class.setup(environment)
    result = ::Sass.compile_string(input[:source], **{
      syntax: :css,
      url: Condenser::Sass::Importer.url(Condenser::Sass::Importer::SCHEME, input[:filename]),
      logger: @logger || Condenser::Sass::Logger.new(environment.logger)
    }.merge(@sass_options))

    input[:source] = result.css
  rescue ::Sass::CompileError => e
    raise Condenser::Sass.compile_error(e, input[:filename])
  end

end
