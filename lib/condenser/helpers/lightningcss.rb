# frozen_string_literal: true

# What Condenser::LightningCSSExporter and Condenser::LightningCSSMinifier
# share: loading the `lightningcss` gem, building the `LightningCSS.transform`
# options and running it with condenser's warnings and errors.
module Condenser::LightningCSS

  # The oldest lightningcss gem that applies targets without minifying,
  # accepts minor versions and gives errors a location.
  MINIMUM_VERSION = '1.33.0.2'

  # The `LightningCSS.transform` options condenser sets, to why.
  RESERVED_OPTIONS = {
    filename: "condenser sets it to the asset's",
    css_modules: "the class names an exported stylesheet uses can't be renamed"
  }.freeze

  # Loads the lightningcss gem, raising a LoadError naming +processor+ if
  # it's missing or too old.
  def self.require_lightningcss!(processor)
    begin
      require 'lightningcss' unless defined?(::LightningCSS::Backend)
    rescue LoadError
      raise LoadError, "#{processor} requires the lightningcss gem, add `gem 'lightningcss', '>= #{MINIMUM_VERSION}'` to your Gemfile"
    end

    if Gem::Version.new(::LightningCSS::VERSION) < Gem::Version.new(MINIMUM_VERSION)
      raise LoadError, "#{processor} requires lightningcss #{MINIMUM_VERSION} or later, #{::LightningCSS::VERSION} is installed"
    end
  end

  # The lightningcss gem's version, which is the version of Lightning CSS it
  # bundles. Raises a LoadError naming +processor+ if it's missing or too old.
  def self.version(processor)
    require_lightningcss!(processor)
    ::LightningCSS::VERSION
  end

  # Returns the frozen `LightningCSS.transform` options, with the +targets+
  # sorted so their order doesn't change the pipeline digest. Raises an
  # ArgumentError if +options+ has a key in +reserved+, a Hash of the keys
  # condenser sets to why.
  def self.transform_options(processor, reserved, targets:, **options)
    options.each_key do |key|
      next unless (instead = reserved[key.to_sym])
      raise ArgumentError, "#{processor.demodulize} options can't include #{key.inspect}, #{instead}"
    end

    options[:targets] = targets.transform_keys(&:to_s).sort.to_h if targets
    options.freeze
  end

  # Transforms the input's source, logging warnings with their location and
  # raising a Condenser::SyntaxError for invalid CSS.
  def self.transform(environment, input, **options)
    result = ::LightningCSS.transform(input[:source], filename: input[:filename], **options)

    result.warnings.each do |warning|
      environment.logger.warn(located_message(warning.message, warning.location, input[:filename]))
    end

    input[:source] = result.code
  rescue ::LightningCSS::ParseError => e
    raise syntax_error(e, input[:filename])
  end

  # Returns "file:line:column: message", or the message prefixed with
  # +filename+ if there's no location. Location columns count from 0, the
  # message shows them from 1 as Lightning CSS's own messages do.
  def self.located_message(message, location, filename)
    if location
      "#{location.filename || filename}:#{location.line}:#{location.column + 1}: #{message}"
    else
      "#{filename}: #{message}"
    end
  end

  def self.syntax_error(error, filename)
    location = error.location
    # The gem's message ends with " at <location>"
    message = location ? error.message.delete_suffix(" at #{location}") : error.message

    syntax_error = Condenser::SyntaxError.new(located_message(message, location, filename))
    syntax_error.set_backtrace(["/assets/#{filename}:#{location&.line || 1}"] + caller)
    syntax_error.instance_variable_set(:@path, "/assets/#{filename}")
    syntax_error
  end
  private_class_method :located_message, :syntax_error

end
