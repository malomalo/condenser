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
class Condenser::LightningCSSExporter

  RESERVED_OPTIONS = Condenser::LightningCSS::RESERVED_OPTIONS

  def self.setup(environment)
    require_lightningcss!
  end

  MINIMUM_VERSION = Condenser::LightningCSS::MINIMUM_VERSION

  def self.require_lightningcss!
    Condenser::LightningCSS.require_lightningcss!(name)
  end

  # The lightningcss gem's version, which is the version of Lightning CSS it
  # bundles. Raises a LoadError if it isn't installed or is too old.
  def self.version
    Condenser::LightningCSS.version(name)
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
    # Condenser doesn't set up exporters, so the gem is loaded (and its
    # version checked) here instead of in #call.
    self.class.require_lightningcss!

    @transform_options = Condenser::LightningCSS.transform_options(self.class.name, RESERVED_OPTIONS, targets: targets, **{ minify: false }.merge(options))
    @options = @transform_options.merge(lightningcss: self.class.version).freeze
  end

  def name
    self.class.name
  end

  def call(environment, input)
    Condenser::LightningCSS.transform(environment, input, **@transform_options)
  end

end
