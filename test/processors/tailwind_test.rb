require 'test_helper'

class TailwindTest < ActiveSupport::TestCase

  module SpawnSpy
    def spawn(*args, **kwargs)
      Thread.current[:tailwind_spawn_args]&.push(args)
      super.tap { |pid| Thread.current[:tailwind_spawns]&.push(pid) }
    end
  end
  Process.singleton_class.prepend(SpawnSpy)

  module BuildSpy
    def call(environment, input)
      super.tap { |result| Thread.current[:tailwind_builds]&.push(input[:filename]) if result }
    end
  end
  Condenser::TailwindProcessor.prepend(BuildSpy)

  def setup
    super
    @tailwind = Condenser::TailwindProcessor.new(@env.npm_path)
    @env.register_preprocessor 'text/css', @tailwind
  end

  def teardown
    super
    Thread.current[:tailwind_spawns] = nil
    Thread.current[:tailwind_spawn_args] = nil
    Thread.current[:tailwind_builds] = nil
    FileUtils.remove_entry(@cache_dir, true) if @cache_dir
    FileUtils.remove_entry(@other, true) if @other
    @app_envs&.each do |env|
      [env.build_cache.instance_variable_get(:@listener), *env.build_cache.instance_variable_get(:@watch_listeners)].compact.each(&:stop)
    end
  end

  def css(env = @env)
    env.find('application.css').source
  end

  # A new process, with a persistent cache shared with the other new ones.
  def new_env
    @cache_dir ||= File.realpath(Dir.mktmpdir)
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, cache: Condenser::Cache::FileStore.new(@cache_dir))
    env.register_preprocessor 'text/css', @tailwind
    env
  end

  # An app laid out like a Rails app, with the stylesheets in
  # app/assets/stylesheets as the load path and the environment's base the
  # app's root, so the rest of app/ isn't on the load path. With +cache+ it's
  # a new process with a persistent cache shared with the other new ones.
  def app_env(tailwind, cache: false, base: @path)
    FileUtils.mkdir_p(File.join(@path, 'app/assets/stylesheets'))
    store = if cache
      @cache_dir ||= File.realpath(Dir.mktmpdir)
      Condenser::Cache::FileStore.new(@cache_dir)
    end
    env = Condenser.new(File.join(@path, 'app/assets/stylesheets'), logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: base, cache: store)
    env.register_preprocessor 'text/css', tailwind
    (@app_envs ||= []) << env
    env
  end

  def app_css(env)
    env.find('application.css').source
  end

  test 'utility classes used in the templates are compiled' do
    file 'views/index.html', '<div class="flex p-4 text-red-500"></div>'
    file 'application.css', '@import "tailwindcss";'

    source = css
    assert_includes source, "/*! tailwindcss v#{@tailwind.options[:tailwindcss]}"
    assert_includes source, ".flex {\n    display: flex;\n  }"
    assert_includes source, ".p-4 {\n    padding: calc(var(--spacing) * 4);\n  }"
    assert_includes source, ".text-red-500 {\n    color: var(--color-red-500);\n  }"
    assert_not_includes source, '.grid {'
  end

  test '@apply and minify' do
    file 'application.css', <<~CSS
      @import "tailwindcss" source(none);
      .btn { @apply px-4 font-bold; }
    CSS
    @env.unregister_preprocessor 'text/css', @tailwind
    @env.register_preprocessor 'text/css', Condenser::TailwindProcessor.new(@env.npm_path, minify: true)

    source = css
    assert_includes source, '.btn{padding-inline:calc(var(--spacing) * 4);--tw-font-weight:var(--font-weight-bold);font-weight:var(--font-weight-bold)}'
    assert_not_includes source, "\n  "
  end

  test 'a stylesheet that does not import tailwindcss is not changed' do
    file 'views/index.html', '<div class="flex"></div>'
    file 'application.css', ".a { @apply flex; }\n"
    pids = Thread.current[:tailwind_spawns] = []

    assert_equal ".a { @apply flex; }\n", css
    assert_empty pids
  end

  test 'the files and directories Tailwind scans are dependencies' do
    file 'views/index.html', '<div class="flex"></div>'
    file 'views/users/show.html.erb', '<div class="grid"></div>'
    file 'application.css', '@import "tailwindcss";'

    asset = @env.find('application.css')
    asset.process
    assert_equal [File.join(@path, 'views/index.html'), File.join(@path, 'views/users/show.html.erb')], asset.file_dependencies.reject { |f| f.include?('/node_modules/') }.sort
    assert_includes asset.file_dependencies, File.join(@npm_dir, 'node_modules/tailwindcss/index.css')
    assert_includes asset.directory_dependencies.map(&:first), File.join(@path, 'views')
  end

  test 'a directory with scanned files is a dependency unless a glob covers it' do
    file 'top.html', '<div class="flex"></div>'
    file 'views/users/deep/show.html', '<div class="grid"></div>'
    file 'components/cards/a.html', '<div class="hidden"></div>'
    file 'application.css', <<~CSS
      @import "tailwindcss";
      @source "./components/cards/*.html";
    CSS

    asset = @env.find('application.css')
    asset.process
    assert_equal [
      [File.join(@path, ''), ['*'], false],
      [File.join(@path, 'components'), true],
      [File.join(@path, 'components/cards'), ['*.html'], false],
      [File.join(@path, 'views'), true]
    ], asset.directory_dependencies.map { |d, globs, recursive| recursive ? [d, recursive] : [d, globs, recursive] }.sort_by(&:first)
  end

  test 'a class added to a template rebuilds the CSS' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'views/index.html', '<div class="flex"></div>'
    file 'application.css', '@import "tailwindcss";'

    assert_not_includes css, '.grid {'
    file 'views/index.html', '<div class="flex grid"></div>'
    assert wait_until { css.include?('.grid {') }
  end

  test 'a new file in a scanned directory rebuilds the CSS' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'views/index.html', '<div class="flex"></div>'
    file 'application.css', '@import "tailwindcss";'

    assert_not_includes css, '.grid {'
    file 'views/users/new/show.html', '<div class="grid"></div>'
    assert wait_until { css.include?('.grid {') }
    file 'views/edit.html', '<div class="hidden"></div>'
    assert wait_until { css.include?('.hidden {') }
  end

  test 'a new process rebuilds the CSS after a template gains a class or a file is added' do
    file 'views/index.html', '<div class="flex"></div>'
    file 'application.css', '@import "tailwindcss";'

    assert_not_includes css(new_env), '.grid {'
    file 'views/index.html', '<div class="flex grid"></div>'
    assert_includes css(new_env), '.grid {'
    file 'views/users/new/show.html', '<div class="hidden"></div>'
    assert_includes css(new_env), '.hidden {'
  end

  test 'a @source directory that is created later is scanned' do
    file 'application.css', <<~CSS
      @import "tailwindcss" source(none);
      @source "./components/{cards,lists}/*.html";
    CSS

    assert_not_includes css(new_env), '.grid {'
    file 'components/lists/a.html', '<div class="grid"></div>'
    assert_includes css(new_env), '.grid {'
  end

  test 'a template outside the load path is scanned with @source and noticed when watched' do
    skip 'needs a listener' if !@env.build_cache.listening
    @other = File.realpath(Dir.mktmpdir)
    @env.watch(@other)
    file 'components/card.html', '<div class="flex"></div>', base: @other
    file 'application.css', <<~CSS
      @import "tailwindcss" source(none);
      @source "#{File.join(@other, 'components')}";
    CSS

    assert_includes css, '.flex {'
    file 'components/card.html', '<div class="grid"></div>', base: @other
    assert wait_until { css.include?('.grid {') }
    assert_not_includes css, '.flex {'
  end

  test 'a scanned directory that is not watched is logged' do
    skip 'needs a listener' if !@env.build_cache.listening
    @other = File.realpath(Dir.mktmpdir)
    file 'card.html', '<div class="flex"></div>', base: @other
    file 'application.css', %(@import "tailwindcss" source("#{@other}");)
    log = StringIO.new
    @env.logger = Logger.new(log)

    css
    assert_includes log.string, "Tailwind scans #{@other}, which isn't watched"
  end

  # An app's root with a Rails app's .gitignore, and files with classes in
  # the gitignored directories.
  def gitignored_app(base = @path, gitignore: true)
    file 'app/views/index.html', '<div class="flex"></div>', base: base
    file 'log/development.log', 'class="grid"', base: base
    file 'log/.keep', '', base: base
    file 'tmp/cache/entry.html', '<div class="grid"></div>', base: base
    file 'storage/ab/cd.html', '<div class="grid"></div>', base: base
    file 'node_modules/pkg/card.html', '<div class="italic"></div>', base: base
    file '.gitignore', "/log/*\n/tmp/*\n/storage/*\n!/log/.keep\nnode_modules\n", base: base if gitignore
  end

  def directory_dependencies(asset)
    asset.directory_dependencies.map { |d, *| d.delete_prefix(@path) }.sort
  end

  def ignored?(dir)
    %w[/log /tmp /storage /node_modules].any? { |d| dir == d || dir.start_with?("#{d}/") }
  end

  test 'gitignored directories found by automatic source detection are not dependencies' do
    gitignored_app
    file 'application.css', '@import "tailwindcss";'

    asset = @env.find('application.css')
    asset.process
    assert_includes asset.source, '.flex {'
    assert_not_includes asset.source, '.grid {'
    assert_includes asset.file_dependencies, File.join(@path, 'app/views/index.html')
    assert_not_includes asset.file_dependencies, File.join(@path, 'log/.keep')
    assert_includes directory_dependencies(asset), '/app'
    assert_empty directory_dependencies(asset).select { |d| ignored?(d) }
  end

  test 'a file added to a gitignored directory does not rebuild the CSS in a new process' do
    gitignored_app
    file 'application.css', '@import "tailwindcss";'
    assert_includes css(new_env), '.flex {'
    key = new_env.find('application.css').process_cache_version
    builds = Thread.current[:tailwind_builds] = []

    file 'log/test.log', 'class="hidden"'
    file 'log/new.html', '<div class="hidden"></div>'
    file 'tmp/new.html', '<div class="hidden"></div>'
    file 'storage/ef/gh.html', '<div class="hidden"></div>'
    file 'node_modules/other/index.html', '<div class="hidden"></div>'
    assert_equal key, new_env.find('application.css').process_cache_version
    assert_not_includes css(new_env), '.hidden {'
    assert_empty builds

    file 'app/views/users/show.html', '<div class="hidden"></div>'
    assert_includes css(new_env), '.hidden {'
    assert_equal ['application.css'], builds
  end

  test 'an explicit @source in a gitignored directory is a dependency' do
    gitignored_app
    file 'application.css', <<~CSS
      @import "tailwindcss";
      @source "./node_modules/pkg";
    CSS

    asset = new_env.find('application.css')
    assert_includes asset.source, '.italic {'
    assert_includes asset.file_dependencies, File.join(@path, 'node_modules/pkg/card.html')
    assert_includes directory_dependencies(asset), '/node_modules/pkg'
    assert_empty directory_dependencies(asset).select { |d| ignored?(d) && !d.start_with?('/node_modules/pkg') }

    file 'node_modules/pkg/card.html', '<div class="underline"></div>'
    assert_includes css(new_env), '.underline {'
    file 'node_modules/pkg/sub/new.html', '<div class="hidden"></div>'
    assert_includes css(new_env), '.hidden {'
  end

  test 'a nested .gitignore applies to its directory' do
    file 'app/views/index.html', '<div class="flex"></div>'
    file 'app/cache/a/b.html', '<div class="grid"></div>'
    file 'app/.gitignore', "/cache/*\n"
    file 'application.css', '@import "tailwindcss";'

    asset = new_env.find('application.css')
    assert_not_includes asset.source, '.grid {'
    assert_includes directory_dependencies(asset), '/app/views'
    assert_empty directory_dependencies(asset).select { |d| d.start_with?('/app/cache') }
  end

  test 'without a .gitignore every directory Tailwind reports is a dependency' do
    gitignored_app(gitignore: false)
    file 'application.css', '@import "tailwindcss";'

    asset = @env.find('application.css')
    asset.process
    assert_includes asset.source, '.grid {'
    assert_includes directory_dependencies(asset), '/app'
    %w[/log /tmp /storage].each do |dir|
      assert directory_dependencies(asset).any? { |d| d == dir || d.start_with?("#{dir}/") }, "#{dir} isn't a dependency"
    end
  end

  test 'the CSS is the same as without the gitignored directories' do
    gitignored_app
    file 'application.css', '@import "tailwindcss";'
    source = css(new_env)

    %w[log tmp storage node_modules .gitignore].each { |f| FileUtils.rm_r(File.join(@path, f)) }
    assert_equal source, css(new_env)
  end

  test 'gitignored directories are not logged as unwatched' do
    skip 'needs a listener' if !@env.build_cache.listening
    @other = File.realpath(Dir.mktmpdir)
    gitignored_app(@other)
    file 'application.css', %(@import "tailwindcss" source("#{@other}");)
    log = StringIO.new
    @env.logger = Logger.new(log)

    css
    warned = log.string.scan(/Tailwind scans (\S+), which isn't watched/).flatten.map { |d| d.delete_prefix(@other) }
    assert_includes warned, '/app'
    assert_empty warned.select { |d| ignored?(d) }
  end

  test 'gitignored directories in sources: are not dependencies, with the .gitignore files above them' do
    file 'app/views/index.html.erb', '<div class="flex"></div>'
    file 'app/tmp/a/b.html', '<div class="grid"></div>'
    file 'app/cache/a/b.html', '<div class="grid"></div>'
    file 'app/.gitignore', "/cache/*\n"
    file '.gitignore', "/app/tmp/*\n"
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: ['app']))

    asset = env.find('application.css')
    assert_includes asset.source, '.flex {'
    assert_not_includes asset.source, '.grid {'
    assert_includes directory_dependencies(asset), '/app'
    assert_includes directory_dependencies(asset), '/app/views'
    assert_empty directory_dependencies(asset).select { |d| d.start_with?('/app/tmp', '/app/cache') }
  end

  test 'a gitignored directory given as a source: is a dependency, with what is in it' do
    file 'vendor/ui/button.html', '<div class="flex"></div>'
    file 'vendor/ui/cards/card.html', '<div class="grid"></div>'
    file '.gitignore', "/vendor/\n"
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: ['vendor/ui']))

    asset = env.find('application.css')
    assert_includes asset.source, '.flex {'
    assert_includes asset.source, '.grid {'
    assert_includes asset.file_dependencies, File.join(@path, 'vendor/ui/cards/card.html')
    assert_includes directory_dependencies(asset), '/vendor/ui'
    assert_includes directory_dependencies(asset), '/vendor/ui/cards'
  end

  test '.gitignore files above the repository a source: is in do not apply' do
    file 'repo/.git/HEAD', ''
    file 'repo/app/views/index.html', '<div class="flex"></div>'
    file 'repo/app/cache/a.html', '<div class="grid"></div>'
    file '.gitignore', "/repo/app/cache/*\n"
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: ['repo/app']))

    asset = env.find('application.css')
    assert_includes asset.source, '.grid {'
    assert_includes asset.file_dependencies, File.join(@path, 'repo/app/cache/a.html')
    assert_includes directory_dependencies(asset), '/repo/app/cache'
  end

  test 'a stylesheet with @reference compiles @apply without Tailwind\'s CSS and without scanning' do
    file 'views/index.html', '<div class="grid"></div>'
    file 'tailwind.css', <<~CSS
      @import "tailwindcss";
      @theme { --color-brand: #3366ff; }
    CSS
    file 'application.css', <<~CSS
      @reference "./tailwind.css";
      .btn { @apply px-4 text-brand; }
    CSS

    asset = @env.find('application.css')
    source = asset.source
    assert_includes source, ".btn {\n  padding-inline: calc(var(--spacing, 0.25rem) * 4);\n  color: var(--color-brand, #3366ff);\n}"
    assert_not_includes source, '.grid {'
    assert_not_includes source, '@layer theme'
    assert_not_includes source, 'box-sizing: border-box'
    assert_not_includes source, '--color-red-500'
    assert_includes asset.file_dependencies, File.join(@path, 'tailwind.css')
    assert_not_includes asset.file_dependencies, File.join(@path, 'views/index.html')
    assert_empty asset.directory_dependencies
  end

  test 'a change to the @theme of a referenced stylesheet rebuilds the CSS' do
    file 'tailwind.css', <<~CSS
      @import "tailwindcss";
      @theme { --color-brand: #3366ff; }
    CSS
    file 'application.css', <<~CSS
      @reference "./tailwind.css";
      .btn { @apply text-brand; }
    CSS

    assert_includes css(new_env), '#3366ff'
    file 'tailwind.css', <<~CSS
      @import "tailwindcss";
      @theme { --color-brand: #ff6633; }
    CSS
    assert_includes css(new_env), '#ff6633'
  end

  test 'a change to the @theme of a referenced stylesheet rebuilds the CSS with the listener' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'tailwind.css', <<~CSS
      @import "tailwindcss";
      @theme { --color-brand: #3366ff; }
    CSS
    file 'application.css', <<~CSS
      @reference "./tailwind.css";
      .btn { @apply text-brand; }
    CSS

    assert_includes css, '#3366ff'
    file 'tailwind.css', <<~CSS
      @import "tailwindcss";
      @theme { --color-brand: #ff6633; }
    CSS
    assert wait_until { css.include?('#ff6633') }
  end

  test '@reference with @import "tailwindcss" still compiles and scans for utilities' do
    file 'views/index.html', '<div class="grid"></div>'
    file 'theme.css', '@theme { --color-brand: #3366ff; }'
    file 'application.css', <<~CSS
      @import "tailwindcss";
      @reference "./theme.css";
      .btn { @apply text-brand; }
    CSS

    asset = @env.find('application.css')
    source = asset.source
    assert_includes source, "/*! tailwindcss v#{@tailwind.options[:tailwindcss]}"
    assert_includes source, 'box-sizing: border-box'
    assert_includes source, ".grid {\n    display: grid;\n  }"
    assert_includes source, ".btn {\n  color: var(--color-brand, #3366ff);\n}"
    assert_includes asset.file_dependencies, File.join(@path, 'views/index.html')
    assert_includes asset.file_dependencies, File.join(@path, 'theme.css')
  end

  test 'a Tailwind error is raised with the file name and the node process is kept' do
    file 'application.css', <<~CSS
      @import "tailwindcss" source(none);
      .btn { @apply not-a-utility; }
    CSS
    pids = Thread.current[:tailwind_spawns] = []

    error = assert_raises(Condenser::Error) { css }
    assert_equal 'application.css: Cannot apply unknown utility class `not-a-utility`', error.message
    file 'application.css', <<~CSS
      @import "tailwindcss" source(none);
      .btn { @apply flex; }
    CSS
    assert_includes css, 'display: flex'
    assert_equal 1, pids.size
  end

  test 'the installed package versions are in the options' do
    versions = %w[tailwindcss @tailwindcss/node @tailwindcss/oxide ignore].to_h do |package|
      [package.to_sym, JSON.parse(File.read(File.join(@npm_dir, 'node_modules', package, 'package.json')))['version']]
    end
    assert_equal({ minify: false, sources: [], **versions }, @tailwind.options)
    assert_match(/\A4\./, @tailwind.options[:tailwindcss])
  end

  test 'the node process runs without a heap size flag' do
    file 'views/index.html', '<div class="flex"></div>'
    file 'application.css', '@import "tailwindcss";'
    spawned = Thread.current[:tailwind_spawn_args] = []

    css
    node = Condenser::NodeProcessor.new(@env.npm_path)
    assert_equal [[node.binary, Condenser::TailwindProcessor::SCRIPT, node.npm_module_path]], spawned
  end

  test 'one node process builds every stylesheet and stop_workers stops it' do
    file 'views/index.html', '<div class="flex"></div>'
    file 'application.css', '@import "tailwindcss";'
    file 'other.css', '@import "tailwindcss";'
    pids = Thread.current[:tailwind_spawns] = []

    css
    @env.find('other.css').source
    assert_equal 1, pids.size
    assert_equal 1, Process.kill(0, pids.first)

    Condenser::NodeWorker.stop_workers
    assert_raises(Errno::ESRCH) { Process.kill(0, pids.first) }
  end

  test 'without sources: the environment base is scanned and not watched' do
    file 'app/views/index.html.erb', '<div class="flex"></div>'
    file 'lib/card.html', '<div class="grid"></div>'
    file 'card.html', '<div class="hidden"></div>'
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir))

    asset = env.find('application.css')
    source = asset.source
    assert_includes source, ".flex {\n    display: flex;\n  }"
    assert_includes source, '.grid {'
    assert_includes source, '.hidden {'
    assert_includes asset.file_dependencies, File.join(@path, 'app/views/index.html.erb')
    assert_includes asset.file_dependencies, File.join(@path, 'lib/card.html')
    assert_empty env.watched_paths
  end

  test 'without sources: an unwatched environment base is logged' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'card.html', '<div class="flex"></div>'
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir))
    log = StringIO.new
    env.logger = Logger.new(log)

    app_css(env)
    assert_includes log.string, "Tailwind scans #{@path}, which isn't watched"
  end

  test 'base: is not an option' do
    error = assert_raises(ArgumentError) { Condenser::TailwindProcessor.new(@npm_dir, base: @path) }
    assert_equal 'unknown keyword: :base', error.message
  end

  test 'sources: are scanned instead of the environment base and recorded as dependencies' do
    @other = File.realpath(Dir.mktmpdir)
    file 'app/views/index.html.erb', '<div class="flex"></div>'
    file 'lib/components/card.html', '<div class="grid"></div>'
    file 'lib/other.html', '<div class="block"></div>'
    file 'card.html', '<div class="italic"></div>'
    file 'views/show.html.erb', '<div class="hidden"></div>', base: @other
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: ['app', 'lib/components', File.join(@other, 'views')]))

    asset = env.find('application.css')
    source = asset.source
    assert_includes source, '.flex {'
    assert_includes source, ".grid {\n    display: grid;\n  }"
    assert_includes source, '.hidden {'
    assert_not_includes source, '.block {'
    assert_not_includes source, '.italic {'
    assert_includes asset.file_dependencies, File.join(@path, 'lib/components/card.html')
    assert_includes asset.file_dependencies, File.join(@other, 'views/show.html.erb')
    assert_not_includes asset.file_dependencies, File.join(@path, 'card.html')
    dirs = asset.directory_dependencies.map(&:first)
    assert_includes dirs, File.join(@path, 'lib/components')
    assert_includes dirs, File.join(@other, 'views')
    assert_not_includes dirs, File.join(@path, '')
    assert_not_includes dirs, @path
  end

  test 'sources: are scanned with source(none)' do
    file 'lib/components/card.html', '<div class="grid"></div>'
    file 'app/views/index.html.erb', '<div class="flex"></div>'
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss" source(none);'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: ['lib/components']))

    source = app_css(env)
    assert_includes source, '.grid {'
    assert_not_includes source, '.flex {'
  end

  test 'source(...) on the import replaces the environment base and sources: are still scanned' do
    file 'app/views/index.html.erb', '<div class="flex"></div>'
    file 'lib/components/card.html', '<div class="grid"></div>'
    file 'card.html', '<div class="hidden"></div>'
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss" source("../../views");'

    assert_includes app_css(app_env(Condenser::TailwindProcessor.new(@npm_dir))), '.flex {'
    assert_not_includes app_css(app_env(Condenser::TailwindProcessor.new(@npm_dir))), '.hidden {'

    source = app_css(app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: ['lib/components'])))
    assert_includes source, '.flex {'
    assert_includes source, '.grid {'
    assert_not_includes source, '.hidden {'
  end

  test '@source paths in the stylesheet are scanned with sources:' do
    file 'app/views/index.html.erb', '<div class="flex"></div>'
    file 'lib/components/card.html', '<div class="grid"></div>'
    file 'vendor/ui/button.html', '<div class="hidden"></div>'
    file 'app/assets/stylesheets/application.css', <<~CSS
      @import "tailwindcss";
      @source "../../../vendor/ui";
      @source not "../../views";
    CSS
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: ['app', 'lib/components']))

    source = app_css(env)
    assert_includes source, '.grid {'
    assert_includes source, '.hidden {'
    assert_not_includes source, '.flex {'
  end

  test 'sources: are watched, so an edit or a new file there rebuilds the CSS' do
    skip 'needs a listener' if !@env.build_cache.listening
    @other = File.realpath(Dir.mktmpdir)
    file 'views/show.html.erb', '<div class="flex"></div>', base: @other
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    FileUtils.mkdir_p(File.join(@path, 'lib'))
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: [File.join(@other, 'views'), 'lib']))
    log = StringIO.new
    env.logger = Logger.new(log)

    assert_not_includes app_css(env), '.grid {'
    assert_equal [[File.join(@other, 'views'), []], [File.join(@path, 'lib'), []]], env.watched_paths
    file 'views/show.html.erb', '<div class="grid"></div>', base: @other
    assert wait_until { app_css(env).include?('.grid {') }
    file 'lib/components/card.html', '<div class="hidden"></div>'
    assert wait_until { app_css(env).include?('.hidden {') }
    assert_not_includes log.string, "isn't watched"
  end

  test 'sources: rebuild the CSS in a new process after an edit or a new file' do
    file 'lib/components/card.html', '<div class="flex"></div>'
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    tailwind = Condenser::TailwindProcessor.new(@npm_dir, sources: ['lib/components'])

    assert_not_includes app_css(app_env(tailwind, cache: true)), '.grid {'
    file 'lib/components/card.html', '<div class="flex grid"></div>'
    assert_includes app_css(app_env(tailwind, cache: true)), '.grid {'
    file 'lib/components/lists/list.html', '<div class="hidden"></div>'
    assert_includes app_css(app_env(tailwind, cache: true)), '.hidden {'
  end

  test 'sources: are watched when the CSS comes from the cache after a restart' do
    skip 'needs a listener' if !@env.build_cache.listening
    @other = File.realpath(Dir.mktmpdir)
    file 'views/show.html.erb', '<div class="flex"></div>', base: @other
    file 'app/views/index.html.erb', '<div class="block"></div>'
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    tailwind = Condenser::TailwindProcessor.new(@npm_dir, sources: ['app', File.join(@other, 'views')])
    assert_includes app_css(app_env(tailwind, cache: true)), '.flex {'
    Condenser::NodeWorker.stop_workers

    pids = Thread.current[:tailwind_spawns] = []
    env = app_env(tailwind, cache: true)
    assert_includes app_css(env), '.flex {'
    assert_empty pids
    assert_includes env.watched_paths, [File.join(@other, 'views'), []]
    assert_includes env.watched_paths, [File.join(@path, 'app'), []]

    file 'views/show.html.erb', '<div class="grid"></div>', base: @other
    assert wait_until { app_css(env).include?('.grid {') }
    file 'app/views/index.html.erb', '<div class="hidden"></div>'
    assert wait_until { app_css(env).include?('.hidden {') }
  end

  test 'sources: are in the options and the pipeline digest, relative to the environment base' do
    a = Condenser::TailwindProcessor.new(@npm_dir)
    b = Condenser::TailwindProcessor.new(@npm_dir, sources: [Pathname.new('lib/components')])
    c = Condenser::TailwindProcessor.new(@npm_dir, sources: [File.join(@path, 'lib/components')])
    assert_equal [], a.options[:sources]
    assert_equal ['lib/components'], b.options[:sources]
    assert_equal [File.join(@path, 'lib/components')], c.options[:sources]

    digests = [a, b, c].map { |p| @env.pipeline_digest_for([[:preprocessor, 'text/css', p]]) }
    assert_equal 3, digests.uniq.size

    @other = File.realpath(Dir.mktmpdir)
    other = Condenser.new(@other, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @other)
    moved = Condenser::TailwindProcessor.new(@npm_dir, sources: [File.join(@other, 'lib/components')])
    assert_equal digests[2], other.pipeline_digest_for([[:preprocessor, 'text/css', moved]])
  end

  test 'a source: that does not exist raises' do
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: ['lib/components']))

    error = assert_raises(Condenser::Error) { app_css(env) }
    assert_equal "TailwindProcessor source lib/components isn't a directory (#{File.join(@path, 'lib/components')})", error.message
  end

  test 'a source: that is a file raises' do
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    file 'card.html', '<div class="flex"></div>'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: ['card.html']))

    error = assert_raises(Condenser::Error) { app_css(env) }
    assert_equal "TailwindProcessor source card.html isn't a directory (#{File.join(@path, 'card.html')})", error.message
  end

  test 'without an environment base automatic source detection needs sources:' do
    file 'app/views/index.html.erb', '<div class="flex"></div>'
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir), base: nil)

    error = assert_raises(Condenser::Error) { app_css(env) }
    assert_match(/\Aapplication\.css: .*automatic source detection, which needs the environment's base or the TailwindProcessor's sources:/, error.message)
    assert_empty env.watched_paths
  end

  test 'without an environment base absolute sources: are scanned' do
    file 'app/views/index.html.erb', '<div class="flex"></div>'
    file 'card.html', '<div class="hidden"></div>'
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss";'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: [File.join(@path, 'app')]), base: nil)

    source = app_css(env)
    assert_includes source, '.flex {'
    assert_not_includes source, '.hidden {'
  end

  test 'without an environment base a relative source: raises' do
    file 'lib/components/card.html', '<div class="grid"></div>'
    file 'app/assets/stylesheets/application.css', '@import "tailwindcss" source(none);'
    env = app_env(Condenser::TailwindProcessor.new(@npm_dir, sources: ['lib/components']), base: nil)

    error = assert_raises(Condenser::Error) { app_css(env) }
    assert_equal "TailwindProcessor source lib/components is relative, which needs the environment's base", error.message
  end
end
