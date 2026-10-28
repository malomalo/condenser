# frozen_string_literal: true

# Minifies CSS with [Lightning CSS](https://lightningcss.dev) through the
# `lightningcss` gem's native (Rust) bindings. It's the default `text/css`
# minifier:
#
#     register_minifier 'text/css', Condenser::LightningCSSMinifier.new
#
# or, with browser targets to lower modern syntax for:
#
#     register_minifier 'text/css', Condenser::LightningCSSMinifier.new(targets: { safari: 15.4, chrome: 100 })
#
# `new` takes `targets:`, as for Condenser::LightningCSSExporter, and other
# `LightningCSS.transform` options, e.g. `error_recovery`. `filename`,
# `css_modules` and `minify` raise an ArgumentError.
class Condenser::LightningCSSMinifier < Condenser::LightningCSSExporter

  RESERVED_OPTIONS = Condenser::LightningCSSExporter::RESERVED_OPTIONS.merge(
    minify: 'the minifier always minifies'
  ).freeze

  DEFAULT_OPTIONS = {}.freeze
  FORCED_OPTIONS = { minify: true }.freeze

end
