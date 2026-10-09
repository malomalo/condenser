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

  attr_reader :options

  # logger - Sass logger for warnings. Defaults to the environment's logger.
  # options - Options passed to Dart Sass, e.g. `style` (default :compressed).
  def initialize(logger: nil, **options)
    @logger = logger
    @options = {
      style: :compressed
    }.merge(options).freeze
  end

  def name
    self.class.name
  end

  def call(environment, input)
    self.class.setup(environment)
    result = ::Sass.compile_string(input[:source], **{
      syntax: :css,
      logger: @logger || Condenser::Sass::Logger.new(environment.logger)
    }.merge(@options))

    input[:source] = result.css
  end

end
