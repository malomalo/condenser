# frozen_string_literal: true

class Condenser::SassMinifier

  def self.setup(environment)
    Condenser::Sass.require_sass_embedded!(name)
  end

  def self.instance
    @instance ||= new
  end

  def self.call(environment, input)
    setup(environment)
    instance.call(environment, input)
  end

  attr_reader :options

  def initialize(options = {})
    options = options.dup
    @logger = options.delete(:logger)
    @options = {
      style: :compressed
    }.merge(options).freeze
  end

  def name
    self.class.name
  end

  def call(environment, input)
    result = ::Sass.compile_string(input[:source], **{
      syntax: :css,
      logger: @logger || Condenser::Sass::Logger.new(environment.logger)
    }.merge(@options))

    input[:source] = result.css
  end

end
