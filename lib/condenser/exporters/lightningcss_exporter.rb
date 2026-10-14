# frozen_string_literal: true

# Transforms CSS with [Lightning CSS](https://lightningcss.dev) through the
# `lightningcss` gem's native (Rust) bindings, for a set of browser targets:
# modern syntax (nesting, lab() colors, ...) is lowered and vendor prefixes
# are added for the targets.
#
# It's registered as an instance, as an exporter so it runs once on the
# complete CSS:
#
#     register_exporter 'text/css', Condenser::LightningCSSExporter.new(targets: { safari: 15.4, chrome: 100 })
#
# To also minify with Lightning CSS pass `minify: true` and unregister the
# 'text/css' minifier.
class Condenser::LightningCSSExporter

  RESERVED_OPTIONS = {
    filename: "condenser sets it to the asset's",
    css_modules: "the class names an exported stylesheet uses can't be renamed"
  }.freeze

  def self.setup(environment)
    require_lightningcss!
  end

  # The oldest lightningcss gem that applies targets without minifying,
  # accepts minor versions and gives errors a location.
  MINIMUM_VERSION = '1.33.0.2'

  def self.require_lightningcss!
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
  def self.version
    require_lightningcss!
    ::LightningCSS::VERSION
  end

  # The targets, Lightning CSS options and version, which are part of the
  # export pipeline digest.
  attr_reader :options

  # targets - Hash of browser to version, the oldest browsers to transform the
  #           CSS for, e.g. `{ safari: 15.4, chrome: 100 }`. A version is a
  #           major version (Integer), or a Float or String with the minor and
  #           patch versions (`15.4`, `"15.4.1"`). The browsers are android,
  #           chrome, edge, firefox, ie, ios_saf, opera, safari and samsung.
  #           Default nil, which keeps the CSS as written.
  # options - Options passed to `LightningCSS.transform`, e.g. `minify`
  #           (default false), `error_recovery` or `scope`. `filename` and
  #           `css_modules` raise an ArgumentError.
  def initialize(targets: nil, **options)
    options.each_key do |key|
      next unless (instead = RESERVED_OPTIONS[key.to_sym])
      raise ArgumentError, "LightningCSSExporter options can't include #{key.inspect}, #{instead}"
    end

    @transform_options = { minify: false }.merge(options)
    @transform_options[:targets] = targets.transform_keys(&:to_s).sort.to_h if targets
    @transform_options.freeze
    @options = @transform_options.merge(lightningcss: self.class.version).freeze
  end

  def name
    self.class.name
  end

  def call(environment, input)
    self.class.setup(environment)
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
