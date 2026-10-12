# frozen_string_literal: true

# Transforms CSS with [Lightning CSS](https://lightningcss.dev) through the
# `lightningcss` gem's native (Rust) bindings, for a set of browser targets:
# modern syntax (nesting, lab() colors, ...) is lowered and vendor prefixes
# are added for the targets.
#
# It's meant to be registered as an exporter so it runs once on the complete
# CSS:
#
#     register_exporter 'text/css', Condenser::LightningCSSExporter.new(targets: { safari: 15, chrome: 100 })
#
# The gem only applies the targets when it minifies, so the output is always
# minified and the 'text/css' minifier can be unregistered.
class Condenser::LightningCSSExporter

  RESERVED_OPTIONS = {
    filename: "condenser sets it to the asset's",
    css_modules: "the class names an exported stylesheet uses can't be renamed"
  }.freeze

  # The gem prints errors and warnings as "message at file:line:column",
  # with 0-based lines.
  LOCATION = /\s+at\s+(?<file>.*):(?<line>\d+):(?<column>\d+)\z/

  def self.setup(environment)
    require_lightningcss!
  end

  def self.require_lightningcss!
    require 'lightningcss' unless defined?(::LightningCSS::Backend)
  rescue LoadError
    raise LoadError, "#{name} requires the lightningcss gem, add `gem 'lightningcss'` to your Gemfile"
  end

  # The lightningcss gem's version, or nil if it isn't installed. The gem's
  # version is the version of Lightning CSS it bundles.
  def self.version
    require 'lightningcss/version' unless defined?(::LightningCSS::VERSION)
    ::LightningCSS::VERSION
  rescue LoadError
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

  # The targets, Lightning CSS options and version, which are part of the
  # export pipeline digest.
  attr_reader :options

  # targets - Hash of browser to major version, the oldest browsers to
  #           transform the CSS for, e.g. `{ safari: 15, chrome: 100 }`. The
  #           browsers are android, chrome, edge, firefox, ie, ios_saf,
  #           opera, safari and samsung. Default nil, which keeps the CSS as
  #           written.
  # options - Options passed to `LightningCSS.transform`, e.g.
  #           `error_recovery` or `scope`. `minify` defaults to true and
  #           must be true when there are targets. `filename` and
  #           `css_modules` raise an ArgumentError.
  def initialize(targets: nil, **options)
    options.each_key do |key|
      next unless (instead = RESERVED_OPTIONS[key.to_sym])
      raise ArgumentError, "LightningCSSExporter options can't include #{key.inspect}, #{instead}"
    end

    @transform_options = { minify: true }.merge(options)
    if targets && !@transform_options[:minify]
      raise ArgumentError, "LightningCSSExporter needs `minify: true` for targets, the lightningcss gem only applies targets when it minifies"
    end

    @transform_options[:targets] = targets.transform_keys(&:to_s).sort.to_h if targets
    @transform_options.freeze
    @options = @transform_options.merge(lightningcss: self.class.version).compact.freeze
  end

  def name
    self.class.name
  end

  def call(environment, input)
    self.class.setup(environment)
    result = ::LightningCSS.transform(input[:source], filename: input[:filename], **@transform_options)

    result.warnings.each do |warning|
      environment.logger.warn(located_message(warning, input[:filename]))
    end

    input[:source] = result.code
  rescue ::LightningCSS::ParseError => e
    raise syntax_error(e, input[:filename])
  end

  private

  # Returns "file:line:column: message" with a 1-based line, or the message
  # prefixed with +filename+ if it has no location.
  def located_message(message, filename)
    if (match = LOCATION.match(message))
      "#{match[:file]}:#{match[:line].to_i + 1}:#{match[:column]}: #{match.pre_match}"
    else
      "#{filename}: #{message}"
    end
  end

  def syntax_error(error, filename)
    match = LOCATION.match(error.message)
    line = match ? match[:line].to_i + 1 : 1

    syntax_error = Condenser::SyntaxError.new(located_message(error.message, filename))
    syntax_error.set_backtrace(["/assets/#{filename}:#{line}"] + caller)
    syntax_error.instance_variable_set(:@path, "/assets/#{filename}")
    syntax_error
  end

end
