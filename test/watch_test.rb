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

end
