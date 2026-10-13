require 'test_helper'

class ListenerTest < ActiveSupport::TestCase

  # Stands in for rb-inotify and the kernel: an event only reaches a watched
  # directory, and like rb-inotify a new directory is watched after its event
  # is handled. +between+ runs just before that watch is added.
  class FakeNotifier
    Watcher = Struct.new(:path)
    Event = Struct.new(:watcher, :name, :flags, :cookie) do
      def absolute_name
        File.join(watcher.path, name)
      end
    end

    attr_reader :started

    def initialize
      @watches = {}
      @started = Queue.new
    end

    def watch(path, *flags, &callback)
      Dir.each_child(path) do |name|
        child = File.join(path, name)
        watch(child, *flags, &callback) if File.directory?(child)
      end
      @watches[path] = callback
    end

    def run
      @started << true
    end

    def close
    end

    def created(path, between: nil)
      callback = @watches[File.dirname(path)] or return
      dir = File.directory?(path)
      callback.call(Event.new(Watcher.new(File.dirname(path)), File.basename(path), dir ? [:create, :isdir] : [:create], 0))
      return if !dir

      between&.call
      watch(path, &callback)
    end
  end

  def setup
    super
    @env.unregister_minifier('text/css')
    skip 'needs a listener' if !@env.build_cache.listening
  end

  def css
    @env.find('test.css').source
  end

  test 'a recursive glob import notices a file in a new directory' do
    file 'dir/a.scss', '.a { color: green; }'
    file 'test.scss', '@import "dir/**/*";'
    assert_includes css, '.a'

    file 'dir/new/b.scss', '.b { color: blue; }'
    assert wait_until { css.include?('.b') }, css

    file 'dir/new/deeper/c.scss', '.c { color: red; }'
    assert wait_until { css.include?('.c') }, css
  end

  test 'a file written to a new directory before inotify watches it is noticed' do
    file 'dir/a.scss', '.a { color: green; }'
    file 'test.scss', '@import "dir/**/*";'
    assert_includes css, '.a'
    @env.build_cache.instance_variable_get(:@listener).stop

    notifier = FakeNotifier.new
    adapter = Listen::Adapter::Linux.new(Listen::Adapter::Config.new([@path], queue = Queue.new, Listen::Silencer.new, {}))
    adapter.instance_variable_set(:@worker, notifier)
    adapter.define_singleton_method(:_configure) { |dir, &callback| @worker.watch(dir.to_s, *options.events, &callback) }
    adapter.start
    notifier.started.pop

    FileUtils.mkdir_p(File.join(@path, 'dir/new'))
    notifier.created(File.join(@path, 'dir/new'), between: -> {
      File.write(File.join(@path, 'dir/new/b.scss'), '.b { color: blue; }')
      notifier.created(File.join(@path, 'dir/new/b.scss'))
      FileUtils.mkdir_p(File.join(@path, 'dir/new/deeper'))
      File.write(File.join(@path, 'dir/new/deeper/c.scss'), '.c { color: red; }')
      notifier.created(File.join(@path, 'dir/new/deeper/c.scss'))
      notifier.created(File.join(@path, 'dir/new/deeper'))
    })

    added = []
    added << queue.pop until queue.empty?
    added = added.select { |_, change| change == :added }.map { |_, _, dir, path| File.join(dir, path) }
    assert_equal %w(dir/new/b.scss dir/new/deeper/c.scss).map { |f| File.join(@path, f) }, added.uniq.sort

    @env.build_cache.instance_variable_get(:@on_change).call([], added, [])
    assert_includes css, '.b'
    assert_includes css, '.c'
  ensure
    adapter&.stop
  end

  test 'a file added to a load path that shares a prefix with another is noticed' do
    root = File.realpath(Dir.mktmpdir)
    FileUtils.mkdir_p([File.join(root, 'assets'), File.join(root, 'assets2')])
    env = Condenser.new(File.join(root, 'assets'), File.join(root, 'assets2'), logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: root)
    skip 'needs a listener' if !env.build_cache.listening
    assert_nil env.find('b.txt')

    File.write(File.join(root, 'assets2', 'b.txt'), 'b')
    env.build_cache.instance_variable_get(:@on_change).call([], [File.join(root, 'assets2', 'b.txt')], [])
    assert env.find('b.txt')
  ensure
    FileUtils.remove_entry(root, true) if root
  end

  test 'a file added under nested load paths is noticed by both' do
    root = File.realpath(Dir.mktmpdir)
    FileUtils.mkdir_p(File.join(root, 'assets', 'js'))
    env = Condenser.new(File.join(root, 'assets'), File.join(root, 'assets', 'js'), logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: root)
    skip 'needs a listener' if !env.build_cache.listening
    assert_nil env.find('x.txt')
    assert_nil env.find('js/x.txt')

    File.write(File.join(root, 'assets', 'js', 'x.txt'), 'x')
    env.build_cache.instance_variable_get(:@on_change).call([], [File.join(root, 'assets', 'js', 'x.txt')], [])
    assert env.find('js/x.txt')
    assert env.find('x.txt')
  ensure
    FileUtils.remove_entry(root, true) if root
  end

  test 'a recursive glob import notices a file removed from a subdirectory' do
    file 'dir/a.scss', '.a { color: green; }'
    file 'dir/sub/deeper/b.scss', '.b { color: blue; }'
    file 'test.scss', '@import "dir/**/*";'
    assert_includes css, '.b'

    rm 'dir/sub/deeper/b.scss'
    assert wait_until { !css.include?('.b') }, css
  end

  test 'a glob import in a subdirectory notices a file in a new directory' do
    file 'styles/dir/a.scss', '.a { color: green; }'
    file 'test.scss', '@import "styles/dir/**/*";'
    assert_includes css, '.a'

    file 'styles/dir/new/b.scss', '.b { color: blue; }'
    assert wait_until { css.include?('.b') }, css
  end

  test 'a one level glob import does not import a file in a new directory' do
    file 'dir/a.scss', '.a { color: green; }'
    file 'test.scss', '@import "dir/*";'
    assert_includes css, '.a'

    file 'dir/new/b.scss', '.b { color: blue; }'
    file 'dir/c.scss', '.c { color: red; }'
    assert wait_until { css.include?('.c') }, css
    assert_not_includes css, '.b'
  end

  test 'a directory dependency under a watched path notices a file in a new directory' do
    root = File.realpath(Dir.mktmpdir)
    @env.watch(root)
    @env.register_preprocessor 'text/plain', Class.new {
      define_singleton_method(:setup) { |env| }
      define_singleton_method(:name) { 'ListingProcessor' }
      define_singleton_method(:call) do |env, input|
        input[:directory_dependencies] << { path: root, glob: '*.html' }
        input[:source] = Dir.glob('**/*.html', base: root).sort.join(',')
      end
    }
    file 'a.html', 'a', base: root
    file 'test.txt', ''
    assert_equal 'a.html', @env.find('test.txt').source

    file 'new/b.html', 'b', base: root
    assert wait_until { @env.find('test.txt').source == 'a.html,new/b.html' }, @env.find('test.txt').source
  ensure
    FileUtils.remove_entry(root, true) if root
  end

  test 'a file dependency recorded through a symlinked path notices changes' do
    root = File.realpath(Dir.mktmpdir)
    link = File.join(File.realpath(Dir.mktmpdir), 'link')
    File.symlink(root, link)
    @env.watch(link)
    @env.register_preprocessor 'text/plain', Class.new {
      define_singleton_method(:setup) { |env| }
      define_singleton_method(:name) { 'SymlinkProcessor' }
      define_singleton_method(:call) do |env, input|
        input[:file_dependencies] << File.join(link, 'a.html')
        input[:source] = File.read(File.join(link, 'a.html'))
      end
    }
    file 'a.html', 'a', base: root
    file 'test.txt', ''
    assert_equal 'a', @env.find('test.txt').source

    file 'a.html', 'b', base: root
    assert wait_until { @env.find('test.txt').source == 'b' }, @env.find('test.txt').source
  ensure
    FileUtils.remove_entry(root, true) if root
    FileUtils.remove_entry(File.dirname(link), true) if link
  end

end
