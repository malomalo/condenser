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

module NpmInstallSpy
  def npm_install(*packages)
    spy = Thread.current[:npm_install_spy]
    spy ? spy.call(npm_path, packages.flatten) : super
  end
end
Condenser::NodeProcessor.prepend(NpmInstallSpy)

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

  test "condenser's version is part of the pipeline digests, cache key and etag" do
    file 'main.js', "console.log(1);\n"
    entries = env.find('main.js').pipeline_processors
    digests = lambda do
      environment = env
      asset = environment.find('main.js')
      [environment.pipline_digest, environment.pipeline_digest_for(entries), environment.export_pipeline_digest('application/javascript'), asset.cache_key, asset.etag]
    end

    before = digests.call
    assert_equal before, digests.call

    stub_const(Condenser, :VERSION, '0.0.0') do
      digests.call.zip(before).each { |after, digest| assert_not_equal digest, after }
    end
  end

  def rolldown_npm_dir(version)
    file 'npm/node_modules/rolldown/package.json', JSON.generate({ name: 'rolldown', version: version })
    File.join(@path, 'npm')
  end

  def bump_rolldown(npm_dir, version)
    package = File.join(npm_dir, 'node_modules', 'rolldown', 'package.json')
    mtime = File.stat(package).mtime
    file 'npm/node_modules/rolldown/package.json', JSON.generate({ name: 'rolldown', version: version })
    File.utime(mtime + 1, mtime + 1, package)
  end

  test 'a class-registered RolldownProcessor puts the Rolldown version in the export digest and etag' do
    file 'main.js', "console.log(1);\n"
    npm_dir = rolldown_npm_dir('0.0.1')
    environment = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: npm_dir, base: @path)
    assert_equal Condenser::RolldownProcessor, environment.exporters['application/javascript'].first

    digest = environment.export_pipeline_digest('application/javascript')
    etag = environment.find('main.js').etag
    assert_equal '0.0.1', Condenser::RolldownProcessor.options_for(environment)[:rolldown]

    unchanged = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: npm_dir, base: @path)
    assert_equal digest, unchanged.export_pipeline_digest('application/javascript')
    assert_equal etag, unchanged.find('main.js').etag

    bump_rolldown(npm_dir, '0.0.2')
    assert_not_equal digest, environment.export_pipeline_digest('application/javascript')

    upgraded = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: npm_dir, base: @path)
    assert_not_equal digest, upgraded.export_pipeline_digest('application/javascript')
    assert_not_equal etag, upgraded.find('main.js').etag
  end

  test 'a class-registered and an instance-registered RolldownProcessor give the same options and digest' do
    npm_dir = rolldown_npm_dir('0.0.1')
    by_class = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: npm_dir, base: @path)
    by_instance = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: npm_dir, base: @path)
    by_instance.unregister_exporter('application/javascript')
    by_instance.register_exporter('application/javascript', Condenser::RolldownProcessor.new(npm_dir))

    assert_equal Condenser::RolldownProcessor.new(npm_dir).options, Condenser::RolldownProcessor.options_for(by_class)
    assert_equal by_instance.export_pipeline_digest('application/javascript'), by_class.export_pipeline_digest('application/javascript')

    bump_rolldown(npm_dir, '0.0.2')
    assert_equal by_instance.export_pipeline_digest('application/javascript'), by_class.export_pipeline_digest('application/javascript')
  end

  # Records npm installs instead of running them, installing a fake Rolldown
  def spy_npm_installs(version: '1.2.3')
    installs = []
    Thread.current[:npm_install_spy] = lambda do |npm_path, packages|
      installs << [npm_path, packages]
      package = File.join(npm_path, 'node_modules', 'rolldown', 'package.json')
      FileUtils.mkdir_p(File.dirname(package))
      File.write(package, JSON.generate({ name: 'rolldown', version: version }))
    end
    installs
  end

  def teardown
    Thread.current[:npm_install_spy] = nil
    super
  end

  test 'a class-registered RolldownProcessor installs Rolldown once, when a digest first needs its version' do
    file 'main.js', "console.log(1);\n"
    npm_dir = File.realpath(Dir.mktmpdir)
    installs = spy_npm_installs
    environment = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: npm_dir, base: @path)
    assert_empty installs

    etag = environment.find('main.js').etag
    assert_equal [[npm_dir, ['rolldown']]], installs
    assert_equal '1.2.3', Condenser::RolldownProcessor.options_for(environment)[:rolldown]

    assert_equal etag, Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: npm_dir, base: @path).find('main.js').etag
    assert_equal 1, installs.size
  ensure
    FileUtils.remove_entry(npm_dir, true)
  end

  test 'an instance-registered RolldownProcessor installs Rolldown on its first digest, not when constructed' do
    npm_dir = File.realpath(Dir.mktmpdir)
    installs = spy_npm_installs
    processor = Condenser::RolldownProcessor.new(npm_dir)
    assert_empty installs

    assert_equal '1.2.3', processor.options[:rolldown]
    processor.options
    assert_equal [[npm_dir, ['rolldown']]], installs
  ensure
    FileUtils.remove_entry(npm_dir, true)
  end

  test 'a RolldownProcessor installs Rolldown before its first build' do
    file 'main.js', "console.log(1);\n"
    npm_dir = File.realpath(Dir.mktmpdir)
    installs = spy_npm_installs
    environment = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: npm_dir, base: @path)
    Condenser::RolldownProcessor::Runner.any_instance.expects(:call).once.with { installs.size == 1 }.returns({})

    Condenser::RolldownProcessor.call(environment, {})
    assert_equal [[npm_dir, ['rolldown']]], installs
  ensure
    FileUtils.remove_entry(npm_dir, true)
  end

  test 'a RolldownProcessor with a bundler_path never installs Rolldown' do
    file 'wrapped-rolldown/package.json', JSON.generate({ name: 'rolldown', version: '0.0.1' })
    npm_dir = File.realpath(Dir.mktmpdir)
    installs = spy_npm_installs
    processor = Condenser::RolldownProcessor.new(npm_dir, bundler_path: File.join(@path, 'wrapped-rolldown'))
    Condenser::RolldownProcessor::Runner.any_instance.stubs(:call).returns({})

    assert_equal '0.0.1', processor.options[:rolldown]
    processor.call(@env, {})
    assert_empty installs
  ensure
    FileUtils.remove_entry(npm_dir, true)
  end

end
