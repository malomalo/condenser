# frozen_string_literal: true

# What Condenser::LightningCSSExporter and Condenser::LightningCSSMinifier
# share: loading the `lightningcss` gem, building the `LightningCSS.transform`
# options and running it with condenser's warnings and errors.
#
# An including class can set:
#
# RESERVED_OPTIONS - Hash of the options it doesn't accept, to why.
# DEFAULT_OPTIONS  - Hash of options the given options are merged into.
# FORCED_OPTIONS   - Hash of options merged over the given options.
module Condenser::LightningCSSProcessor

  # The oldest lightningcss gem that applies targets without minifying,
  # accepts minor versions and gives errors a location.
  MINIMUM_VERSION = '1.33.0.2'

  # The `LightningCSS.transform` options condenser sets, to why.
  RESERVED_OPTIONS = {
    filename: "condenser sets it to the asset's",
    css_modules: "the class names an exported stylesheet uses can't be renamed"
  }.freeze

  DEFAULT_OPTIONS = {}.freeze
  FORCED_OPTIONS = {}.freeze

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods

    def setup(environment)
      require_lightningcss!
    end

    # Loads the lightningcss gem, raising a LoadError naming the class if
    # it's missing or too old.
    def require_lightningcss!
      begin
        require 'lightningcss' unless defined?(::LightningCSS::Backend)
      rescue LoadError
        raise LoadError, "#{name} requires the lightningcss gem, add `gem 'lightningcss', '>= #{MINIMUM_VERSION}'` to your Gemfile"
      end

      if Gem::Version.new(::LightningCSS::VERSION) < Gem::Version.new(MINIMUM_VERSION)
        raise LoadError, "#{name} requires lightningcss #{MINIMUM_VERSION} or later, #{::LightningCSS::VERSION} is installed"
      end
    end

    # The lightningcss gem's version, which is the version of Lightning CSS it
    # bundles. Raises a LoadError if it isn't installed or is too old.
    def version
      require_lightningcss!
      ::LightningCSS::VERSION
    end

  end

  # The targets, Lightning CSS options and version, which are part of the
  # export pipeline digest.
  attr_reader :options

  # targets - Hash of browser to version, the oldest browsers to transform the
  #           CSS for, e.g. `{ safari: 15.4, chrome: 100 }`. A version is a
  #           major version (Integer), or a Float or String with the minor and
  #           patch versions (`15.4`, `"15.4.1"`). The browsers are android,
  #           chrome, edge, firefox, ie, ios_saf, opera, safari and samsung.
  #           Default nil, which keeps the CSS as written. They're sorted so
  #           their order doesn't change the pipeline digest.
  # options - Options passed to `LightningCSS.transform`. Raises an
  #           ArgumentError for a key in RESERVED_OPTIONS.
  def initialize(targets: nil, **options)
    # Condenser doesn't set up exporters or minifier instances, so the gem is
    # loaded (and its version checked) here instead of in #call.
    version = self.class.version

    options = self.class::DEFAULT_OPTIONS.merge(options)
    options.each_key do |key|
      next unless (instead = self.class::RESERVED_OPTIONS[key.to_sym])
      raise ArgumentError, "#{self.class.name.demodulize} options can't include #{key.inspect}, #{instead}"
    end
    options[:targets] = targets.transform_keys(&:to_s).sort.to_h if targets

    @transform_options = options.merge(self.class::FORCED_OPTIONS).freeze
    @options = @transform_options.merge(lightningcss: version).freeze
  end

  def name
    self.class.name
  end

  # Transforms the input's source, logging warnings with their location and
  # raising a Condenser::SyntaxError for invalid CSS.
  def call(environment, input)
    result = ::LightningCSS.transform(input[:source], filename: input[:filename], **@transform_options)

    result.warnings.each do |warning|
      environment.logger.warn(located_message(warning.message, warning.location, input[:filename]))
    end

    input[:source] = result.code
  rescue ::LightningCSS::ParseError => e
    raise syntax_error(e, input[:filename])
  end

  private

  # Returns "file:line:column: message", or the message prefixed with
  # +filename+ if there's no location. Location columns count from 0, the
  # message shows them from 1 as Lightning CSS's own messages do.
  def located_message(message, location, filename)
    if location
      "#{location.filename || filename}:#{location.line}:#{location.column + 1}: #{message}"
    else
      "#{filename}: #{message}"
    end
  end

  def syntax_error(error, filename)
    location = error.location
    # The gem's message ends with " at <location>"
    message = location ? error.message.delete_suffix(" at #{location}") : error.message

    syntax_error = Condenser::SyntaxError.new(located_message(message, location, filename))
    syntax_error.set_backtrace(["/assets/#{filename}:#{location&.line || 1}"] + caller)
    syntax_error.instance_variable_set(:@path, "/assets/#{filename}")
    syntax_error
  end

end
