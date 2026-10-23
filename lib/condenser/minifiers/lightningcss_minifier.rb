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
#
# `new` takes `targets:`, as for Condenser::LightningCSSExporter, and other
# `LightningCSS.transform` options, e.g. `error_recovery`. `filename`,
# `css_modules` and `minify` raise an ArgumentError.
class Condenser::LightningCSSMinifier

  include Condenser::LightningCSSProcessor

  RESERVED_OPTIONS = Condenser::LightningCSSProcessor::RESERVED_OPTIONS.merge(
    minify: 'the minifier always minifies'
  ).freeze

  FORCED_OPTIONS = { minify: true }.freeze

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

end
