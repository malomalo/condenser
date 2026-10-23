require 'test_helper'

class RolldownDefaultTest < ActiveSupport::TestCase

  def setup
    super
    file 'main.js', "console.log( 'main' );\n"
  end

  def teardown
    ENV['NODE_PATH'] = @node_path if defined?(@node_path)
    super
  end

  # The default RolldownProcessor, without minifying so the output is
  # readable.
  def new_env(**options)
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), base: @path, **options)
    env.unregister_exporter('application/javascript')
    env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(env.npm_path))
    env
  end

  def with_node_path(value)
    @node_path = ENV['NODE_PATH']
    ENV['NODE_PATH'] = value
  end

  test 'Condenser.new exports and minifies JavaScript with a RolldownProcessor' do
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), base: @path, npm_path: @npm_dir)
    exporters = env.exporters['application/javascript']
    assert_equal [Condenser::RolldownProcessor], exporters.map(&:class)
    assert exporters.first.minify?
    assert_nil env.minifier_for('application/javascript')
    assert_equal File.join(@npm_dir, 'node_modules', 'rolldown'), exporters.first.rolldown_path
    assert_equal 'console.log(`main`);', env.find('main.js').export.source
    assert_equal <<~JS, new_env(npm_path: @npm_dir).find('main.js').export.source
      // main.js
      console.log("main");
    JS
  end

  test 'the default RolldownProcessor uses the npm path passed to Condenser.new' do
    with_node_path(@path)
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), base: @path, npm_path: @npm_dir)
    assert_equal File.join(@npm_dir, 'node_modules', 'rolldown'), env.exporters['application/javascript'].first.rolldown_path
    assert_includes env.find('main.js').export.source, 'console.log(`main`);'
  end

  test 'without an npm path rolldown is loaded with node module resolution' do
    with_node_path(File.join(@npm_dir, 'node_modules'))
    assert_includes new_env.find('main.js').export.source, 'console.log("main");'
  end

  test 'without an npm path exporting fails if node cannot find rolldown' do
    with_node_path(@path)
    error = assert_raises(RuntimeError) { new_env.find('main.js').export }
    assert_match "Cannot find module 'rolldown'", error.message
  end

end
