require 'test_helper'

# The `// depends_on` directive, with the load path at app/assets under the
# environment's base, like a Rails app.
class DependsOnTest < ActiveSupport::TestCase

  def setup
    super
    @assets = File.join(@path, 'app/assets')
    @cache_dir = File.realpath(Dir.mktmpdir)
    FileUtils.mkdir_p(@assets)
  end

  def teardown
    super
    FileUtils.remove_entry(@cache_dir, true)
  end

  def new_env(cache: Condenser::Cache::FileStore.new(@cache_dir))
    Condenser.new(@assets, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, cache: cache)
  end

  # A main.js.erb that embeds the secret from +read+ and has +directive+.
  def main(directive, read = 'config/x.yml')
    file 'app/assets/main.js.erb', <<~JS
      // depends_on #{directive}
      console.log(<%= File.read(#{File.join(@path, read).inspect})[/secret-\\w+/].inspect %>);
    JS
  end

  def secret(env)
    env.find('main.js').export.source[/secret-\w+/]
  end

  test 'a file relative to base rebuilds the asset in a new process' do
    file 'config/x.yml', "secret: secret-one\n"
    main 'config/x.yml'

    asset = new_env.find('main.js')
    assert_equal 'secret-one', secret(new_env)
    assert_equal [File.join(@path, 'config/x.yml')], asset.file_dependencies
    assert_equal ['!config/x.yml'], asset.direct_dependency_names[:files]
    assert_equal [], asset.process_dependencies
    assert_not_includes asset.export.source, 'secret: secret-one'

    file 'config/x.yml', "secret: secret-two\n"
    assert_equal 'secret-two', secret(new_env)
  end

  test 'a file relative to base rebuilds the asset with the listener when base is watched' do
    file 'config/x.yml', "secret: secret-one\n"
    main 'config/x.yml'
    env = new_env(cache: Condenser::Cache::MemoryStore.new)
    skip 'needs a listener' if !env.build_cache.listening
    env.watch(@path)

    assert_equal 'secret-one', secret(env)
    file 'config/x.yml', "secret: secret-two\n"
    assert wait_until { secret(env) == 'secret-two' }
  end

  test 'a ! path is relative to base' do
    file 'config/x.yml', "secret: secret-one\n"
    main '!config/x.yml'

    assert_equal 'secret-one', secret(new_env)
    file 'config/x.yml', "secret: secret-two\n"
    assert_equal 'secret-two', secret(new_env)
  end

  test 'an asset in the load path wins over a file relative to base' do
    file 'config/x.yml', "secret: secret-base\n"
    file 'app/assets/config/x.yml', "secret: secret-one\n"
    main 'config/x.yml', 'app/assets/config/x.yml'

    asset = new_env.find('main.js')
    assert_equal [File.join(@assets, 'config/x.yml')], asset.process_dependencies.map(&:source_file)
    assert_equal [], asset.file_dependencies

    file 'config/x.yml', "secret: secret-base-two\n"
    assert_equal 'secret-one', secret(new_env)
    file 'app/assets/config/x.yml', "secret: secret-two\n"
    assert_equal 'secret-two', secret(new_env)
  end

  test 'a ./ path finds an asset relative to the source file' do
    file 'app/assets/x.yml', "secret: secret-one\n"
    main './x.yml', 'app/assets/x.yml'

    asset = new_env.find('main.js')
    assert_equal [File.join(@assets, 'x.yml')], asset.process_dependencies.map(&:source_file)
    file 'app/assets/x.yml', "secret: secret-two\n"
    assert_equal 'secret-two', secret(new_env)
  end

  test 'a missing path raises FileNotFound' do
    file 'app/assets/main.js', "// depends_on config/x.yml\nconsole.log(1);\n"
    error = assert_raises(Condenser::FileNotFound) { new_env.find('main.js').process }
    assert_equal "main.js: couldn't find 'config/x.yml' for // depends_on", error.message
  end

  test 'a missing path raises FileNotFound without a base' do
    file 'config/x.yml', "secret: secret-one\n"
    main 'config/x.yml'
    env = Condenser.new(@assets, logger: Logger.new('/dev/null'), npm_path: @npm_dir, cache: Condenser::Cache::MemoryStore.new)
    error = assert_raises(Condenser::FileNotFound) { env.find('main.js').process }
    assert_equal "main.js: couldn't find 'config/x.yml' for // depends_on", error.message
  end

  test 'a glob matching nothing does not raise or look in base' do
    file 'config/a.yml', "secret: secret-one\n"
    main 'config/*.yml', 'config/a.yml'

    asset = new_env.find('main.js')
    assert_equal 'secret-one', secret(new_env)
    assert_equal [], asset.process_dependencies
    assert_equal [], asset.file_dependencies
  end

  test 'a file only in base is not found by find, resolve, imports, Sass, link_asset, depend_on, depend_on_file or expand_dependency_path' do
    file 'config/x.yml', "secret: secret-one\n"
    env = new_env(cache: Condenser::Cache::MemoryStore.new)

    assert_nil env.find('config/x.yml')
    assert_equal [], env.resolve('config/x.yml')
    assert_raises(Condenser::FileNotFound) { env.find!('config/x.yml') }
    assert_raises(Condenser::FileNotFound) { env.expand_dependency_path('config/x.yml') }

    file 'app/assets/import.js', "import x from 'config/x.yml';\nconsole.log(x);\n"
    error = assert_raises(RuntimeError) { env.find('import.js').export }
    assert_includes error.message, 'config/x.yml'

    rollup = new_env(cache: Condenser::Cache::MemoryStore.new)
    rollup.unregister_exporter('application/javascript')
    rollup.register_exporter('application/javascript', Condenser::RollupProcessor.new(@npm_dir))
    # Rollup leaves an import it can't resolve as an external
    assert_includes rollup.find('import.js').export.source, "import x from 'config/x.yml';"

    file 'app/assets/link.js.erb', "<% link_asset 'config/x.yml' %>console.log(1);\n"
    assert_raises(Condenser::FileNotFound) { env.find('link.js').process }

    file 'app/assets/depend.js.erb', "<% depend_on 'config/x.yml' %>console.log(1);\n"
    assert_raises(Condenser::FileNotFound) { env.find('depend.js').process }

    file 'app/assets/file.js.erb', "<% depend_on_file 'config/x.yml' %>console.log(1);\n"
    assert_raises(Condenser::FileNotFound) { env.find('file.js').process }

    file 'config/_y.scss', "a { color: red; }\n"
    ['@import', '@use'].each do |rule|
      file 'app/assets/main.scss', "#{rule} 'config/y';\n"
      error = assert_raises(StandardError) { env.find('main.css').process }
      assert_includes error.message, "Can't find stylesheet to import"
    end
  end

end
