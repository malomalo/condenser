require 'test_helper'

class TailwindTest < ActiveSupport::TestCase

  module SpawnSpy
    def spawn(*args, **kwargs)
      super.tap { |pid| Thread.current[:tailwind_spawns]&.push(pid) }
    end
  end
  Process.singleton_class.prepend(SpawnSpy)

  def setup
    super
    @tailwind = Condenser::TailwindProcessor.new(@env.npm_path, base: @path)
    @env.register_preprocessor 'text/css', @tailwind
  end

  def teardown
    super
    Thread.current[:tailwind_spawns] = nil
    FileUtils.remove_entry(@cache_dir, true) if @cache_dir
    FileUtils.remove_entry(@other, true) if @other
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

  test 'automatic source detection needs a base' do
    file 'application.css', '@import "tailwindcss";'
    @env.unregister_preprocessor 'text/css', @tailwind
    @env.register_preprocessor 'text/css', Condenser::TailwindProcessor.new(@env.npm_path)

    error = assert_raises(Condenser::Error) { css }
    assert_match(/\Aapplication\.css: .*automatic source detection, which needs the TailwindProcessor's base:/, error.message)
  end

  test 'a stylesheet with @reference compiles @apply without Tailwind\'s CSS and without a base' do
    file 'views/index.html', '<div class="grid"></div>'
    file 'tailwind.css', <<~CSS
      @import "tailwindcss";
      @theme { --color-brand: #3366ff; }
    CSS
    file 'application.css', <<~CSS
      @reference "./tailwind.css";
      .btn { @apply px-4 text-brand; }
    CSS
    @env.unregister_preprocessor 'text/css', @tailwind
    @env.register_preprocessor 'text/css', Condenser::TailwindProcessor.new(@env.npm_path)

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
    versions = %w[tailwindcss @tailwindcss/node @tailwindcss/oxide].to_h do |package|
      [package.to_sym, JSON.parse(File.read(File.join(@npm_dir, 'node_modules', package, 'package.json')))['version']]
    end
    assert_equal({ minify: false, **versions }, @tailwind.options)
    assert_match(/\A4\./, @tailwind.options[:tailwindcss])
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

    Condenser::RolldownProcessor.stop_workers
    assert_raises(Errno::ESRCH) { Process.kill(0, pids.first) }
  end
end
