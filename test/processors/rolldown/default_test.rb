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

  def new_env(**options)
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), base: @path, **options)
    env.unregister_minifier('application/javascript')
    env
  end

  def with_node_path(value)
    @node_path = ENV['NODE_PATH']
    ENV['NODE_PATH'] = value
  end

  test 'Condenser.new exports JavaScript with RolldownProcessor' do
    assert_equal [Condenser::RolldownProcessor], new_env(npm_path: @npm_dir).exporters['application/javascript']
    assert_equal <<~JS, new_env(npm_path: @npm_dir).find('main.js').export.source
      //#region main.js
      console.log("main");
      //#endregion
    JS
  end

  test 'the default RolldownProcessor uses the npm path the environment has when exporting' do
    with_node_path(@path)
    env = new_env
    env.append_npm_path(@npm_dir)
    assert_includes env.find('main.js').export.source, 'console.log("main");'
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
