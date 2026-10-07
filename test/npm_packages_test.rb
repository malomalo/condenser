require 'test_helper'

class NpmPackagesTest < ActiveSupport::TestCase

  def setup
    super
    @npm = File.realpath(Dir.mktmpdir)
    @packages = {}
  end

  def teardown
    super
    FileUtils.remove_entry(@npm, true)
  end

  # Records a package in the lockfile the way `npm install` does
  def install(key, version, dependencies: nil)
    @packages[key] = { 'version' => version, 'resolved' => "https://registry.test/#{key}-#{version}.tgz" }
    @packages[key]['dependencies'] = dependencies if dependencies
    File.write(File.join(@npm, 'package-lock.json'), JSON.generate({ 'lockfileVersion' => 3, 'packages' => @packages }))
  end

  # A new environment each time, like a deploy sharing tmp/cache
  def versions(*names)
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm, base: @path)
    names.to_h do |name|
      asset = env.find(name)
      [name, [asset.etag, asset.export_cache_version]]
    end
  end

  test 'upgrading an imported package changes the etag and export cache key' do
    install 'node_modules/dolla', '1.0.0'
    install 'node_modules/unused', '1.0.0'
    file 'main.js', "import d from 'dolla';\nconsole.log(d);\n"

    before = versions('main.js')
    assert_equal before, versions('main.js')

    install 'node_modules/unused', '2.0.0'
    assert_equal before, versions('main.js')

    install 'node_modules/dolla', '2.0.0'
    assert_not_equal before, versions('main.js')
  end

  test 'the packages an imported package depends on are included' do
    install 'node_modules/komps', '1.0.0', dependencies: { 'dolla' => '^1.0.0' }
    install 'node_modules/dolla', '1.0.0'
    file 'main.js', "import k from 'komps';\nconsole.log(k);\n"

    before = versions('main.js')
    install 'node_modules/dolla', '1.1.0'
    assert_not_equal before, versions('main.js')
  end

  test 'a dependency installed inside a package is used over the top-level one' do
    install 'node_modules/komps', '1.0.0', dependencies: { 'dolla' => '^2.0.0' }
    install 'node_modules/komps/node_modules/dolla', '2.0.0'
    install 'node_modules/dolla', '1.0.0'
    file 'main.js', "import k from 'komps';\nconsole.log(k);\n"

    before = versions('main.js')
    install 'node_modules/dolla', '1.1.0'
    assert_equal before, versions('main.js')

    install 'node_modules/komps/node_modules/dolla', '2.1.0'
    assert_not_equal before, versions('main.js')
  end

  test 'scoped packages and imports of files inside a package are included' do
    install 'node_modules/@floating-ui/dom', '1.0.0'
    file 'main.js', "import { computePosition } from '@floating-ui/dom/dist/floating-ui.dom';\nconsole.log(computePosition);\n"

    before = versions('main.js')
    install 'node_modules/@floating-ui/dom', '1.1.0'
    assert_not_equal before, versions('main.js')
  end

  test 'the packages of a dynamically imported file are part of the importer' do
    install 'node_modules/dolla', '1.0.0'
    file 'child.js', "import d from 'dolla';\nexport default d;\n"
    file 'main.js', "const child = await import('child');\nconsole.log(child);\n"

    before = versions('main.js', 'child.js')
    install 'node_modules/dolla', '2.0.0'
    after = versions('main.js', 'child.js')
    assert_not_equal before['child.js'], after['child.js']
    assert_not_equal before['main.js'], after['main.js']
  end

  test 'assets that import no npm packages are unaffected' do
    install 'node_modules/dolla', '1.0.0'
    file 'other.js', "export default 1;\n"
    file 'main.js', "import o from 'other';\nconsole.log(o);\n"

    no_lockfile = File.realpath(Dir.mktmpdir)
    without_npm = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: no_lockfile, base: @path).find('main.js').etag
    assert_equal without_npm, versions('main.js')['main.js'][0]
  ensure
    FileUtils.remove_entry(no_lockfile, true) if no_lockfile
  end

  test 'without a lockfile, importing files from a package leaves the etag unchanged' do
    FileUtils.mkdir_p(File.join(@npm, 'node_modules', 'dolla'))
    File.write(File.join(@npm, 'node_modules', 'dolla', 'util.js'), "export default 1;\n")
    file 'main.js', "import u from 'dolla/util';\nconsole.log(u);\n"

    asset = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm, base: @path).find('main.js')
    assert_equal ['node_modules/dolla'], asset.npm_package_keys
    assert_nil asset.npm_digest
  end

  test 'a dynamic import kept as its own bundle points at the rebuilt bundle after an upgrade' do
    # Rollup needs a real npm dir: link in the test npm dir's packages, but
    # not its lockfile. Install Rollup there first, or it would be installed
    # into @npm, and npm would remove the package this test adds.
    Condenser::RollupProcessor.install_npm_packages(@npm_dir)
    Dir.mkdir(File.join(@npm, 'node_modules'))
    Dir.children(File.join(@npm_dir, 'node_modules')).each do |name|
      next if name.start_with?('.')
      File.symlink(File.join(@npm_dir, 'node_modules', name), File.join(@npm, 'node_modules', name))
    end
    pkg = File.join(@npm, 'node_modules', 'versioned')
    Dir.mkdir(pkg)
    File.write(File.join(pkg, 'package.json'), '{"name": "versioned", "main": "index.js"}')
    File.write(File.join(pkg, 'index.js'), "export default 'version 1';\n")
    install 'node_modules/versioned', '1.0.0'
    file 'child.js', "import v from 'versioned';\nexport default v;\n"
    file 'main.js', "const child = await import('child');\nconsole.log(child);\n"
    cache = Condenser::Cache::MemoryStore.new

    # Returns the URL main.js embeds, the file child.js is written as, and
    # the version child.js has
    build = lambda do
      env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm, base: @path, cache: cache)
      env.unregister_minifier('application/javascript')
      env.unregister_exporter('application/javascript')
      env.register_exporter('application/javascript', Condenser::RollupProcessor.new(@npm, dynamic_imports: false))
      embedded = env.find('main.js').export.source[/child-\h+\.js/]
      child = env.find('child.js').export
      [embedded, File.basename(child.path), child.source[/version \d/]]
    end

    embedded, written, version = build.call
    assert_equal [written, 'version 1'], [embedded, version]

    File.write(File.join(pkg, 'index.js'), "export default 'version 2';\n")
    install 'node_modules/versioned', '2.0.0'
    new_embedded, new_written, version = build.call
    assert_equal [new_written, 'version 2'], [new_embedded, version]
    assert_not_equal written, new_written
  end

  test 'a running environment picks up an upgraded package' do
    install 'node_modules/dolla', '1.0.0'
    file 'main.js', "import d from 'dolla';\nconsole.log(d);\n"
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm, base: @path)
    etag = env.find('main.js').etag

    install 'node_modules/dolla', '2.0.0-beta'
    assert_not_equal etag, env.find('main.js').etag
  end

end
