require 'test_helper'

# Depends on the files configured for each asset and appends their contents.
class WatchedFilesProcessor
  class << self
    attr_accessor :files
  end

  def self.setup(environment)
  end

  def self.call(environment, input)
    input[:source] = input[:source] + (files[input[:filename]] || []).map do |f|
      input[:file_dependencies] << f
      "#{File.basename(f)}: #{File.file?(f) ? File.read(f).strip : 'missing'}\n"
    end.join
  end
end

class WatchTest < ActiveSupport::TestCase

  def setup
    super
    @root = File.realpath(Dir.mktmpdir)
    WatchedFilesProcessor.files = {}
    @env.register_preprocessor 'text/plain', WatchedFilesProcessor
    skip 'needs a listener' if !@env.build_cache.listening
  end

  def teardown
    super
    FileUtils.remove_entry(@root, true)
  end

  def source(name, env = @env)
    env.find(name).source
  end

  test 'a file dependency outside the load path is not noticed unless it is watched' do
    file 'a.txt', "a\n"
    file 'b.txt', "b\n"
    file 'content/a.html', 'one', base: @root
    WatchedFilesProcessor.files = { 'a.txt' => ["#{@root}/content/a.html"], 'b.txt' => ["#{@path}/b.html"] }

    assert_includes source('a.txt'), 'a.html: one'
    source('b.txt')
    file 'content/a.html', 'two', base: @root
    file 'b.html', 'flushed'
    assert wait_until { source('b.txt').include?('b.html: flushed') }
    assert_includes source('a.txt'), 'a.html: one'
  end

  test 'an edited file under a watched path is noticed by the listener' do
    @env.watch(@root)
    file 'a.txt', "a\n"
    file 'content/a.html', 'one', base: @root
    WatchedFilesProcessor.files = { 'a.txt' => ["#{@root}/content/a.html"] }

    assert_includes source('a.txt'), 'a.html: one'
    file 'content/a.html', 'two', base: @root
    assert wait_until { source('a.txt').include?('a.html: two') }
  end

  test 'a path watched before the listener starts is noticed' do
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), base: @path)
    env.watch(@root)
    env.register_preprocessor 'text/plain', WatchedFilesProcessor
    assert_equal [[@root, []]], env.watched_paths
    file 'a.txt', "a\n"
    file 'a.html', 'one', base: @root
    WatchedFilesProcessor.files = { 'a.txt' => ["#{@root}/a.html"] }

    assert_includes source('a.txt', env), 'a.html: one'
    file 'a.html', 'two', base: @root
    assert wait_until { source('a.txt', env).include?('a.html: two') }
  end

  test 'ignored files under a watched path are not noticed' do
    @env.watch(@root, ignore: ['vendor', /\.log\z/])
    file 'a.txt', "a\n"
    file 'b.txt', "b\n"
    %w(vendor/a.html node_modules/pkg/a.html lib/node_modules/a.html tmp/a.html debug.log watched.html).each do |name|
      file name, 'one', base: @root
    end
    WatchedFilesProcessor.files = {
      'a.txt' => %w(vendor/a.html node_modules/pkg/a.html lib/node_modules/a.html tmp/a.html debug.log).map { |f| "#{@root}/#{f}" },
      'b.txt' => ["#{@root}/watched.html"]
    }

    before = source('a.txt')
    source('b.txt')
    %w(vendor/a.html node_modules/pkg/a.html lib/node_modules/a.html tmp/a.html debug.log).each do |name|
      file name, 'two', base: @root
    end
    file 'watched.html', 'two', base: @root
    assert wait_until { source('b.txt').include?('watched.html: two') }
    assert_equal before, source('a.txt')
  end

  test 'files under a watched path are not assets' do
    @env.watch(@root)
    file 'a.js', "console.log(1);\n", base: @root
    file 'b.js', "console.log(2);\n"

    assert_nil @env.find('a.js')
    assert_not_includes @env.path, @root
    assert_equal "#{@path}/b.js", @env.find('b.js').source_file
  end

  test 'watching a path that does not exist raises' do
    assert_raises(ArgumentError) { @env.watch(File.join(@root, 'missing')) }
  end

  def listeners(env = @env)
    env.build_cache.instance_variable_get(:@watch_listeners).size
  end

  test 'watching the same path twice creates one listener' do
    @env.watch(@root, ignore: ['vendor'])
    @env.watch(@root, ignore: ['lib'])

    assert_equal 1, listeners
    assert_equal [[@root, ['vendor']]], @env.watched_paths
  end

  test 'watching a path under a load path creates no listener' do
    FileUtils.mkdir_p(File.join(@path, 'content'))
    @env.watch(@path, File.join(@path, 'content'))

    assert_equal 0, listeners
  end

  test 'a symlinked path and its real path create one listener' do
    link = File.join(File.realpath(Dir.mktmpdir), 'link')
    File.symlink(@root, link)
    @env.watch(link)
    @env.watch(@root)

    assert_equal 1, listeners
    assert_equal [[link, []]], @env.watched_paths
  ensure
    FileUtils.remove_entry(File.dirname(link), true) if link
  end

  test 'a path watched before the listener starts is watched once' do
    FileUtils.mkdir_p(File.join(@root, 'content'))
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), base: @path)
    env.watch(@root)
    env.watch(@root, File.join(@root, 'content'))

    assert_equal [[@root, []]], env.watched_paths
    assert_equal 1, listeners(env)
  end

  test 'a path under a watched path creates no listener unless it is ignored' do
    %w(content vendor).each { |d| FileUtils.mkdir_p(File.join(@root, d)) }
    @env.watch(@root, ignore: ['vendor'])
    @env.watch(File.join(@root, 'content'))
    assert_equal 1, listeners

    @env.watch(File.join(@root, 'vendor'))
    assert_equal 2, listeners
  end

  test 'a sibling with a shared string prefix gets its own listener' do
    %w(assets assets2 lib lib2).each { |d| FileUtils.mkdir_p(File.join(@root, d)) }
    env = Condenser.new(File.join(@root, 'assets'), logger: Logger.new('/dev/null'), base: @root)
    env.watch(File.join(@root, 'assets2'))
    env.watch(File.join(@root, 'lib'))
    env.watch(File.join(@root, 'lib2'))

    assert_equal 3, listeners(env)
  end

  test 'an edit under paths watched more than once is noticed once and reprocesses its dependents' do
    link = File.join(File.realpath(Dir.mktmpdir), 'link')
    File.symlink(@root, link)
    file 'content/a.html', 'one', base: @root
    file 'a.txt', "a\n"
    file 'main.js', "// depends_on a.txt\nconsole.log(1);\n"
    WatchedFilesProcessor.files = { 'a.txt' => ["#{@root}/content/a.html"] }

    cache = @env.build_cache
    on_change = cache.instance_variable_get(:@on_change)
    changes = []
    cache.instance_variable_set(:@on_change, lambda { |modified, added, removed|
      changes.concat(modified + added)
      on_change.call(modified, added, removed)
    })
    @env.watch(File.join(@root, 'content'))
    @env.watch(@root)
    @env.watch(@root)
    @env.watch(link)
    @env.watch(File.join(link, 'content'))
    assert_equal 2, listeners

    assert_includes source('a.txt'), 'a.html: one'
    version = @env.find('main.js').process_cache_version
    file 'content/a.html', 'two', base: @root
    assert wait_until { source('a.txt').include?('a.html: two') }
    assert_not_equal version, @env.find('main.js').process_cache_version
    sleep 0.5
    assert_equal ["#{@root}/content/a.html"], changes
  ensure
    FileUtils.remove_entry(File.dirname(link), true) if link
  end

end
