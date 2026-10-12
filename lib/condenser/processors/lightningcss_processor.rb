# frozen_string_literal: true

require 'json'

# Transforms CSS with [Lightning CSS](https://lightningcss.dev) for a set of
# browser targets: modern syntax (nesting, oklch(), media query ranges, ...)
# is lowered and vendor prefixes are added for the targets.
#
# It's meant to be registered as an exporter so it runs once on the complete
# CSS, before the minifier:
#
#     register_exporter 'text/css', Condenser::LightningCSSProcessor.new(npm_path, targets: '> 0.5%, last 2 versions')
#
# To also minify with Lightning CSS pass `minify: true` and unregister the
# 'text/css' minifier.
class Condenser::LightningCSSProcessor < Condenser::NodeProcessor

  PACKAGES = %w(lightningcss browserslist).freeze

  RESERVED_OPTIONS = %i(filename code sourceMap).freeze

  # The browserslist query used when no targets are given.
  DEFAULT_TARGETS = 'defaults'

  def self.setup(environment)
    ::Condenser::NodeProcessor.new(environment.npm_path).npm_install(*PACKAGES)
  end

  def self.call(environment, input)
    @instances ||= {}
    @instances[environment] ||= new(environment.npm_path)
    @instances[environment].call(environment, input)
  end

  # The options of the processor registered as a class.
  def self.options
    { targets: DEFAULT_TARGETS }
  end

  # The targets, Lightning CSS options and the versions of the packages that
  # resolve the targets, which are part of the export pipeline digest.
  attr_reader :options

  # dir - String (path to node_modules directory)
  # targets - browserslist query, as a String or Array of Strings, the
  #           browsers to transform the CSS for. Default 'defaults'.
  # options - Options passed to Lightning CSS's `transform`, e.g. `minify`,
  #           `drafts` or `include` / `exclude` features. See
  #           https://lightningcss.dev/transpilation.html. `filename`, `code`
  #           and `sourceMap` are set by condenser and raise an ArgumentError.
  def initialize(dir = nil, targets: DEFAULT_TARGETS, **options)
    super(dir)
    reserved = RESERVED_OPTIONS & options.keys.map(&:to_sym)
    if reserved.any?
      raise ArgumentError, "LightningCSSProcessor options #{reserved.map(&:inspect).join(', ')} are set by condenser"
    end

    npm_install(*PACKAGES)
    @targets = targets
    @transform_options = { minify: false }.merge(options).freeze
    @options = { targets: targets }.merge(@transform_options).merge(package_versions).freeze
  end

  def call(environment, input)
    result = exec_worker(<<-JS, input[:source], input[:filename], @targets, @transform_options)
      const lightningcss = require("#{npm_module_path('lightningcss')}");
      const browserslist = require("#{npm_module_path('browserslist')}");

      const handle = (source, filename, targets, options) => {
        try {
          const result = lightningcss.transform(Object.assign({}, options, {
            filename: filename,
            code: Buffer.from(source),
            targets: lightningcss.browserslistToTargets(browserslist(targets))
          }));
          return { code: result.code.toString(), warnings: result.warnings };
        } catch (e) {
          return { error: { name: e.name, message: e.message, loc: e.loc } };
        }
      };
    JS

    if error = result['error']
      raise lightningcss_error(error, input[:filename])
    end

    result['warnings']&.each do |warning|
      line = warning.dig('loc', 'line')
      environment.logger.warn("#{input[:filename]}#{":#{line}" if line}: #{warning['message']}")
    end

    input[:source] = result['code']
  end

  private

  # Lightning CSS's version, and those of browserslist and caniuse-lite, so
  # the output is rebuilt when the browsers a query resolves to change.
  def package_versions
    %w(lightningcss browserslist caniuse-lite).each_with_object({}) do |package, versions|
      package_json = File.join(npm_module_path(package), 'package.json')
      versions[package] = JSON.parse(File.read(package_json))['version'] if File.exist?(package_json)
    end
  end

  def lightningcss_error(error, filename)
    if error.is_a?(Array)
      # Raised outside of the transform, e.g. by an invalid browserslist query.
      return exec_runtime_error("#{error[0]}: #{error[1]}")
    end

    line = error.dig('loc', 'line') || 1
    message = "#{error['name']}: #{error['message']}"
    if error['name'] == 'SyntaxError'
      syntax_error = Condenser::SyntaxError.new("#{message} (#{line}:#{error.dig('loc', 'column')})")
      syntax_error.set_backtrace(["/assets/#{filename}:#{line}"] + caller)
      syntax_error.instance_variable_set(:@path, "/assets/#{filename}")
      syntax_error
    else
      exec_runtime_error("#{message} (/assets/#{filename}:#{line})")
    end
  end

end
