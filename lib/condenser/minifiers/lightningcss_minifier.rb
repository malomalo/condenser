# frozen_string_literal: true

# Minifies CSS with [Lightning CSS](https://lightningcss.dev) through the
# `lightningcss` gem's native (Rust) bindings. It's the default `text/css`
# minifier:
#
#     register_minifier 'text/css', Condenser::LightningCSSMinifier
#
# or, with browser targets to lower modern syntax for:
#
#     register_minifier 'text/css', Condenser::LightningCSSMinifier.new(targets: { safari: 15.4, chrome: 100 })
class Condenser::LightningCSSMinifier

  RESERVED_OPTIONS = Condenser::LightningCSS::RESERVED_OPTIONS.merge(
    minify: 'the minifier always minifies'
  ).freeze

  def self.setup(environment)
    Condenser::LightningCSS.require_lightningcss!(name)
  end

  # The default minifier is registered as the class, so the gem is only
  # needed once CSS is minified.
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

  # targets - Hash of browser to version, the oldest browsers to transform the
  #           CSS for, as for Condenser::LightningCSSExporter. Default nil,
  #           which keeps the CSS syntax as written.
  # options - Options passed to `LightningCSS.transform`, e.g.
  #           `error_recovery`. `filename`, `css_modules` and `minify` raise
  #           an ArgumentError.
  def initialize(targets: nil, **options)
    version = Condenser::LightningCSS.version(self.class.name)
    @transform_options = Condenser::LightningCSS.transform_options(self.class.name, RESERVED_OPTIONS, targets: targets, **options).merge(minify: true).freeze
    @options = @transform_options.merge(lightningcss: version).freeze
  end

  def name
    self.class.name
  end

  def call(environment, input)
    Condenser::LightningCSS.transform(environment, input, **@transform_options)
  end

end
