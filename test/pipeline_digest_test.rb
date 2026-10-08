require 'test_helper'

# Counts how often it's set up; registered where a test needs a processor.
class CountingProcessor
  class << self
    attr_accessor :setups
  end

  def self.setup(environment)
    self.setups += 1
  end

  def self.call(environment, input)
  end
end

# A processor with options, which are part of the pipeline digest.
class OptionsProcessor
  attr_reader :options

  def initialize(options = {})
    @options = options
  end

  def self.setup(environment)
  end

  def call(environment, input)
  end
end

# A template whose output depends on its options.
class GreetingTemplate
  attr_reader :options

  def initialize(options = {})
    @options = options
  end

  def self.setup(environment)
  end

  def call(environment, input)
    input[:source] = "export default #{JSON.generate(@options[:word])};\n"
  end
end

class PipelineDigestTest < ActiveSupport::TestCase

  def setup
    super
    CountingProcessor.setups = 0
    @cache = Condenser::Cache::MemoryStore.new
  end

  # A new environment sharing the cache, like a deploy sharing tmp/cache
  def env
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, cache: @cache)
    yield env if block_given?
    env
  end

  test 'a processor for a type no asset uses is never set up' do
    file 'main.js', "console.log(1);\n"

    environment = env { |e| e.register_preprocessor('text/x-unused', CountingProcessor) }
    environment.find('main.js').export
    assert_equal 0, CountingProcessor.setups

    environment = env { |e| e.register_preprocessor('application/javascript', CountingProcessor) }
    environment.find('main.js').export
    assert_equal 1, CountingProcessor.setups
  end

  test 'changing a processor for another type keeps the cache key and cached processing' do
    file 'main.js', "console.log(1);\n"

    before = env.find('main.js')
    before.process

    after = env { |e| e.register_transformer('text/scss', 'text/css', OptionsProcessor.new(style: :compressed)) }.find('main.js')
    assert_equal before.cache_key, after.cache_key

    Condenser::JSAnalyzer.expects(:call).never
    after.process
  end

  test 'changing a processor that processes the file changes its cache key' do
    file 'main.js', "console.log(1);\n"

    before = env { |e| e.register_preprocessor('application/javascript', OptionsProcessor.new(a: 1)) }.find('main.js')
    after = env { |e| e.register_preprocessor('application/javascript', OptionsProcessor.new(a: 2)) }.find('main.js')
    assert_not_equal before.cache_key, after.cache_key
  end

  test 'the preprocessors of types a file is transformed into are part of its cache key' do
    # JstTransformer runs the JavaScript preprocessors itself
    file 'template.jst', "<p></p>\n"

    before = env.find('template.js')
    after = env { |e| e.register_preprocessor('application/javascript', OptionsProcessor.new(a: 1)) }.find('template.js')
    assert_not_equal before.cache_key, after.cache_key
  end

  test 'changing the processor of a dependency rebuilds the bundles that include it' do
    file 'greeting.js.greet', "\n"
    file 'main.js', "import greeting from 'greeting';\nconsole.log(greeting);\n"

    build = lambda do |word|
      env { |e|
        e.register_mime_type('application/x-greet', extension: '.greet')
        e.register_template('application/x-greet', GreetingTemplate.new(word: word))
      }.find('main.js').export.source
    end

    assert_includes build.call('hello'), '"hello"'
    assert_includes build.call('goodbye'), '"goodbye"'
  end

  test 'changing the minifier changes the etag and export but reuses the processed file' do
    file 'main.js', "console.log( 1 );\n"

    minified = env.find('main.js')
    minified_export = minified.export

    not_minified = env { |e| e.unregister_minifier('application/javascript') }.find('main.js')
    assert_equal minified.cache_key, not_minified.cache_key

    Condenser::JSAnalyzer.expects(:call).never
    not_minified_export = not_minified.export
    assert_not_equal minified_export.source, not_minified_export.source
    assert_not_equal minified.etag, not_minified.etag
  end

end
