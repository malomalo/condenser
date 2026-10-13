require 'test_helper'

# Records the files and directories it's configured with as dependencies and
# appends what it finds in them to the source.
class FileDependencyProcessor
  class << self
    attr_accessor :files, :directories, :calls
  end

  def self.setup(environment)
  end

  def self.call(environment, input)
    calls[input[:filename]] += 1
    lines = files.map do |f|
      input[:file_dependencies] << f
      "#{File.basename(f)}: #{File.file?(f) ? File.read(f).strip : 'missing'}"
    end
    directories.each do |dir, options|
      input[:directory_dependencies] << { path: dir, **options }
      glob = options[:recursive] ? "**/#{options[:glob] || '*'}" : (options[:glob] || '*')
      lines << "#{File.basename(dir)}: #{Dir.glob(glob, base: dir).select { |f| File.file?(File.join(dir, f)) }.sort.join(',')}"
    end
    input[:source] = input[:source] + lines.join("\n")
  end
end

class FileDependenciesTest < ActiveSupport::TestCase

  def setup
    super
    @content = File.join(@path, 'content')
    FileUtils.mkdir_p(@content)
    FileDependencyProcessor.files = []
    FileDependencyProcessor.directories = {}
    FileDependencyProcessor.calls = Hash.new(0)
    @env.register_preprocessor 'text/plain', FileDependencyProcessor
    file 'test.txt', "test\n"
  end

  def teardown
    super
    FileUtils.remove_entry(@cache_dir, true) if @cache_dir
  end

  def build(env = @env)
    env.find('test.txt').source
  end

  def calls
    FileDependencyProcessor.calls['test.txt']
  end

  def assert_rebuilds_with(expected)
    assert wait_until { build.include?(expected) }, "expected the source to include #{expected.inspect}, got #{build.inspect}"
  end

  # Waits until the listener has seen a change made after the ones before
  # it, by changing an asset that doesn't depend on anything.
  def flush_listener
    file 'sentinel.txt', "before\n"
    before = @env.find('sentinel.txt').source
    file 'sentinel.txt', "after\n"
    assert wait_until { @env.find('sentinel.txt').source != before }
  end

  def new_env
    @cache_dir ||= File.realpath(Dir.mktmpdir)
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, cache: Condenser::Cache::FileStore.new(@cache_dir))
    env.register_preprocessor 'text/plain', FileDependencyProcessor
    env
  end

  test 'a file dependency that changes reprocesses the asset' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'content/a.html', 'one', base: @path
    FileDependencyProcessor.files = [File.join(@content, 'a.html')]

    assert_includes build, 'a.html: one'
    file 'content/a.html', 'two'
    assert_rebuilds_with 'a.html: two'
  end

  test 'a file dependency that is added or removed reprocesses the asset' do
    skip 'needs a listener' if !@env.build_cache.listening
    FileDependencyProcessor.files = [File.join(@content, 'a.html')]

    assert_includes build, 'a.html: missing'
    file 'content/a.html', 'added'
    assert_rebuilds_with 'a.html: added'

    rm 'content/a.html'
    assert_rebuilds_with 'a.html: missing'
  end

  test 'a file dependency is not processed as an asset' do
    file 'content/Gemfile', "gem 'rails'"
    file 'content/a.html.erb', '<%= raise "processed" %>'
    FileDependencyProcessor.files = [File.join(@content, 'Gemfile'), File.join(@content, 'a.html.erb')]

    asset = @env.find('test.txt')
    assert_includes asset.source, "Gemfile: gem 'rails'"
    assert_equal [], asset.process_dependencies
    assert_equal [File.join(@content, 'Gemfile'), File.join(@content, 'a.html.erb')], asset.file_dependencies
  end

  test 'adding or removing a file in a directory dependency reprocesses the asset' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'content/a.html', 'a'
    FileDependencyProcessor.directories = { @content => { glob: '*.html' } }

    assert_includes build, 'content: a.html'
    file 'content/b.html', 'b'
    assert_rebuilds_with 'content: a.html,b.html'

    rm 'content/a.html'
    assert_rebuilds_with 'content: b.html'
  end

  test 'a file in a new subdirectory of a directory dependency reprocesses the asset' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'content/a.html', 'a'
    FileDependencyProcessor.directories = { @content => { glob: '*.html', recursive: true } }

    assert_includes build, 'content: a.html'
    file 'content/new/deeper/b.html', 'b'
    assert_rebuilds_with 'content: a.html,new/deeper/b.html'

    file 'content/new/deeper/c.html', 'c'
    assert_rebuilds_with 'content: a.html,new/deeper/b.html,new/deeper/c.html'
  end

  test 'a new subdirectory changes a directory dependency that is not recursive' do
    file 'content/a.html', 'a'
    FileDependencyProcessor.directories = { @content => { glob: '*.html' } }

    digest = @env.find('test.txt').file_dependencies_digest
    file 'content/new/b.html', 'b'
    assert_not_equal digest, new_env.find('test.txt').file_dependencies_digest
  end

  test 'a file that does not match the glob of a directory dependency does not reprocess the asset' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'content/a.html', 'a'
    FileDependencyProcessor.directories = { @content => { glob: '*.html' } }

    build
    file 'content/b.css', 'b'
    flush_listener
    build
    assert_equal 1, calls
  end

  test 'an unrelated file does not reprocess the asset' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'content/a.html', 'a'
    file 'other/b.html', 'b'
    FileDependencyProcessor.files = [File.join(@content, 'a.html')]
    FileDependencyProcessor.directories = { @content => { glob: '*.html' } }

    build
    file 'other/b.html', 'changed'
    file 'other/c.html', 'c'
    flush_listener
    build
    assert_equal 1, calls
  end

  test 'a persistent cache is used by a new process when the dependencies have not changed' do
    file 'content/a.html', 'a'
    FileDependencyProcessor.files = [File.join(@content, 'a.html')]
    FileDependencyProcessor.directories = { @content => { glob: '*.html' } }

    source = new_env.find('test.txt').export.source
    assert_equal 1, calls
    assert_equal source, new_env.find('test.txt').export.source
    assert_equal 1, calls
  end

  test 'a persistent cache is not used by a new process after a file dependency changed' do
    file 'content/a.html', 'one'
    FileDependencyProcessor.files = [File.join(@content, 'a.html')]

    assert_includes new_env.find('test.txt').export.source, 'a.html: one'
    file 'content/a.html', 'two'
    assert_includes new_env.find('test.txt').export.source, 'a.html: two'
    assert_equal 2, calls

    rm 'content/a.html'
    assert_includes new_env.find('test.txt').export.source, 'a.html: missing'
  end

  test 'a persistent cache is not used by a new process after a directory dependency changed' do
    file 'content/a.html', 'a'
    FileDependencyProcessor.directories = { @content => { glob: '*.html', recursive: true } }

    assert_includes build(new_env), 'content: a.html'
    file 'content/sub/b.html', 'b'
    assert_includes build(new_env), 'content: a.html,sub/b.html'
    rm 'content/a.html'
    assert_includes build(new_env), 'content: sub/b.html'
    assert_equal 3, calls
  end

  test 'a recursive and a non-recursive dependency on the same directory' do
    file 'content/a.html', 'a'
    FileDependencyProcessor.directories = [
      [@content, { glob: '*.html', recursive: true }],
      [@content, { glob: '*.html' }]
    ]

    assert_includes build(new_env), 'content: a.html'
    assert_equal [[@content, ['*.html'], true]], new_env.find('test.txt').directory_dependencies
    file 'content/sub/b.html', 'b'
    assert_includes build(new_env), 'content: a.html,sub/b.html'
  end

  test 'file dependencies of a dependency invalidate the dependent' do
    file 'content/a.html', 'one'
    FileDependencyProcessor.files = [File.join(@content, 'a.html')]
    file 'main.js', "// depends_on test.txt\nconsole.log(1);\n"
    version = new_env.find('main.js').process_cache_version
    assert_equal version, new_env.find('main.js').process_cache_version

    file 'content/a.html', 'two'
    assert_not_equal version, new_env.find('main.js').process_cache_version
  end

  test 'depend_on_file and depend_on_directory in a template' do
    file 'content/a.html', 'one'
    file 'ctx.txt.erb', <<~ERB
      <% depend_on_file '#{@content}/a.html' %><% depend_on_directory '#{@content}', glob: '*.html' %><%= File.read('#{@content}/a.html') %>
    ERB

    asset = @env.find('ctx.txt')
    assert_includes asset.source, 'one'
    assert_equal [File.join(@content, 'a.html')], asset.file_dependencies
    assert_equal [[@content, ['*.html'], false]], asset.directory_dependencies

    file 'content/a.html', 'two'
    assert_includes new_env.find('ctx.txt').source, 'two'
  end

end
