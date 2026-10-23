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
# The default 'text/css' minifier, Condenser::LightningCSSMinifier, also
# takes targets, to lower syntax and minify in one pass.
#
# `new` takes `targets:` and other `LightningCSS.transform` options, e.g.
# `minify` (default false), `error_recovery` or `scope`. `filename` and
# `css_modules` raise an ArgumentError. See Condenser::LightningCSSProcessor.
class Condenser::LightningCSSExporter

  include Condenser::LightningCSSProcessor

  DEFAULT_OPTIONS = { minify: false }.freeze

end
