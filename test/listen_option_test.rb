require 'test_helper'
require 'listen'
require 'rake/condensertask'

class ListenOptionTest < ActiveSupport::TestCase

  def setup
    super
    @root = File.realpath(Dir.mktmpdir)
    @cache_dir = File.realpath(Dir.mktmpdir)
  end

  def teardown
    super
    FileUtils.remove_entry(@root, true)
    FileUtils.remove_entry(@cache_dir, true)
  end

  def new_env(**options)
    Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, **options)
  end

  test 'listen: false starts no listener on the load paths' do
    Listen.expects(:to).never
    env = new_env(listen: false)

    assert_equal false, env.build_cache.listening
    assert_nil env.build_cache.instance_variable_get(:@listener)
  end

  test 'listen: false starts no listener for watched paths' do
    Listen.expects(:to).never
    env = new_env(listen: false)
    env.watch(@root)
    env.build_cache
    env.watch(@cache_dir, ignore: ['x'])

    assert_equal [[@root, []], [@cache_dir, ['x']]], env.watched_paths
    assert_empty env.build_cache.instance_variable_get(:@watch_listeners)
  end

  test 'listen: false builds, and a new process sees changes through the cache' do
    file 'main.js', "import { a } from './a';\nconsole.log(a);\n"
    file 'a.js', "export const a = 'one';\n"

    env = new_env(listen: false, cache: Condenser::Cache::FileStore.new(@cache_dir))
    assert_includes env.find('main.js').export.source, 'one'

    file 'a.js', "export const a = 'two';\n"
    env = new_env(listen: false, cache: Condenser::Cache::FileStore.new(@cache_dir))
    assert_includes env.find('main.js').export.source, 'two'
    refute_includes env.find('main.js').export.source, 'one'
  end

  test 'listens by default when Listen has a native adapter' do
    env = new_env
    native = Listen::Adapter.select != Listen::Adapter::Polling

    assert_equal native, env.build_cache.listening
    assert_equal native, !env.build_cache.instance_variable_get(:@listener).nil?
  ensure
    env&.build_cache&.instance_variable_get(:@listener)&.stop
  end

  test "the rake task's default environment doesn't listen" do
    Listen.expects(:to).never
    task = Rake::CondenserTask.new(:listen_option_assets)

    assert_equal false, task.environment.build_cache.listening
  end

end
