require 'test_helper'

# Records the files and directories it's configured with as dependencies and
# appends what it finds in them to the source.
class FileDependencyProcessor
  class << self
    attr_accessor :files, :directories, :calls, :switches
  end

  def self.setup(environment)
  end

  def self.call(environment, input)
    calls[input[:filename]] += 1
    lines = files.map do |f|
      f, read = Array(f)
      read = (environment.expand_dependency_path(f, source_file: input[:source_file]) rescue nil) if read == :resolve
      read ||= f
      input[:file_dependencies] << f
      "#{File.basename(f)}: #{File.file?(read) ? File.read(read).strip : 'missing'}"
    end
    directories.each do |dir, options|
      dir, recorded = Array(dir).reverse
      dir = (environment.expand_dependency_path(recorded, source_file: input[:source_file], directory: true) rescue recorded) if dir == :resolve
      input[:directory_dependencies] << { path: recorded || dir, **options }
      glob = options[:recursive] ? "**/#{options[:glob] || '*'}" : (options[:glob] || '*')
      lines << "#{File.basename(dir)}: #{Dir.glob(glob, base: dir).select { |f| File.file?(File.join(dir, f)) }.sort.join(',')}"
    end
    if config = switches[input[:filename]]
      input[:file_dependencies] << config
      name = File.read(config).strip
      input[:process_dependencies] << name
      lines << "#{name}: #{environment.find(name).source.strip}"
    end
    input[:source] = input[:source] + lines.join("\n")
  end
end

class FileDependenciesTest < ActiveSupport::TestCase

  # Counts the File.stat and BuildCache.real_path calls for each path while
  # Thread.current[:stats] or [:real_paths] is set.
  module StatSpy
    def stat(path)
      Thread.current[:stats][path.to_s] += 1 if Thread.current[:stats]
      super
    end
  end
  File.singleton_class.prepend(StatSpy)

  module RealPathSpy
    def real_path(path)
      Thread.current[:real_paths][path] += 1 if Thread.current[:real_paths]
      super
    end
  end
  Condenser::BuildCache.singleton_class.prepend(RealPathSpy)

  def setup
    super
    @content = File.join(@path, 'content')
    FileUtils.mkdir_p(@content)
    FileDependencyProcessor.files = []
    FileDependencyProcessor.directories = {}
    FileDependencyProcessor.calls = Hash.new(0)
    FileDependencyProcessor.switches = {}
    @env.register_preprocessor 'text/plain', FileDependencyProcessor
    file 'test.txt', "test\n"
  end

  def teardown
    super
    FileUtils.remove_entry(@cache_dir, true) if @cache_dir
    FileUtils.remove_entry(@second, true) if @second
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
  def flush_listener(env = @env)
    file 'sentinel.txt', "before\n"
    before = env.find('sentinel.txt').source
    file 'sentinel.txt', "after\n"
    assert wait_until { env.find('sentinel.txt').source != before }
  end

  def new_env(*paths, base: @path)
    @cache_dir ||= File.realpath(Dir.mktmpdir)
    paths = [@path] if paths.empty?
    env = Condenser.new(*paths, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: base, cache: Condenser::Cache::FileStore.new(@cache_dir))
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

  def raises_not_found?(env = @env)
    build(env)
    false
  rescue Condenser::FileNotFound
    true
  end

  test 'a file dependency that is added or removed reprocesses the asset' do
    skip 'needs a listener' if !@env.build_cache.listening
    FileDependencyProcessor.files = [File.join(@content, 'a.html')]

    error = assert_raises(Condenser::FileNotFound) { build }
    assert_equal "couldn't find file '#{File.join(@content, 'a.html')}' from #{File.join(@path, 'test.txt')}", error.message
    file 'content/a.html', 'added'
    assert_rebuilds_with 'a.html: added'

    rm 'content/a.html'
    assert wait_until { raises_not_found? }, "expected the rebuild to raise FileNotFound"
    file 'content/a.html', 'added again'
    assert_rebuilds_with 'a.html: added again'
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
    assert_raises(Condenser::FileNotFound) { new_env.find('test.txt').export }
    file 'content/a.html', 'three'
    assert_includes new_env.find('test.txt').export.source, 'a.html: three'
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

  def switching_file_dependency
    file 'content/config', "a.html\n"
    file 'content/a.html', 'one'
    file 'content/b.html', 'two'
    file 'ctx.txt.erb', <<~ERB
      <% depend_on_file '#{@content}/config' %><% name = '#{@content}/' + File.read('#{@content}/config').strip %><% depend_on_file name %><%= File.read(name) %>
    ERB
  end

  test 'a persistent cache is not used by a new process after a file dependency changed the file dependencies' do
    switching_file_dependency

    assert_includes new_env.find('ctx.txt').export.source, 'one'
    file 'content/config', "b.html\n"
    assert_includes new_env.find('ctx.txt').export.source, 'two'
    assert_equal 2, FileDependencyProcessor.calls['ctx.txt']

    asset = new_env.find('ctx.txt')
    assert_includes asset.export.source, 'two'
    assert_equal [File.join(@content, 'b.html'), File.join(@content, 'config')], asset.file_dependencies.sort
    assert_equal 2, FileDependencyProcessor.calls['ctx.txt']

    file 'content/b.html', 'three'
    asset = new_env.find('ctx.txt')
    assert_includes asset.export.source, 'three'
    assert_equal [File.join(@content, 'b.html'), File.join(@content, 'config')], asset.file_dependencies.sort
  end

  test 'a persistent cache is not used by a new process after a file dependency changed the process dependencies' do
    file 'content/config', "a.txt\n"
    file 'a.txt', 'one'
    file 'b.txt', 'two'
    FileDependencyProcessor.switches = { 'test.txt' => File.join(@content, 'config') }

    assert_includes build(new_env), 'a.txt: one'
    file 'content/config', "b.txt\n"
    assert_includes build(new_env), 'b.txt: two'

    file 'b.txt', 'three'
    asset = new_env.find('test.txt')
    assert_includes asset.export.source, 'b.txt: three'
    assert_equal [File.join(@path, 'b.txt')], asset.process_dependencies.map(&:source_file)
  end

  test 'a persistent cache is not used by a new process after a file dependency changed the imports' do
    file 'content/config', "a\n"
    file 'a.js', "export default 'one';\n"
    file 'b.js', "export default 'two';\n"
    file 'main.js.erb', <<~ERB
      <% depend_on_file '#{@content}/config' %>import x from './<%= File.read('#{@content}/config').strip %>';
      console.log(x);
    ERB

    assert_includes new_env.find('main.js').export.source, 'one'
    file 'content/config', "b\n"
    assert_includes new_env.find('main.js').export.source, 'two'

    file 'b.js', "export default 'three';\n"
    assert_includes new_env.find('main.js').export.source, 'three'
  end

  test 'a file dependency that changes the file dependencies is listened to' do
    skip 'needs a listener' if !@env.build_cache.listening
    switching_file_dependency

    assert_includes @env.find('ctx.txt').source, 'one'
    file 'content/config', "b.html\n"
    assert wait_until { @env.find('ctx.txt').source.include?('two') }

    file 'content/b.html', 'three'
    assert wait_until { @env.find('ctx.txt').source.include?('three') }, "expected the new file dependency to reprocess the asset"
    calls = FileDependencyProcessor.calls['ctx.txt']

    file 'content/a.html', 'changed'
    flush_listener
    assert_includes @env.find('ctx.txt').source, 'three'
    assert_equal calls, FileDependencyProcessor.calls['ctx.txt']
  end

  # Runs the block from a directory that isn't a load path or the asset's.
  def in_other_directory
    pwd = Dir.pwd
    other = File.realpath(Dir.mktmpdir)
    Dir.chdir(other)
    yield other
  ensure
    Dir.chdir(pwd)
    FileUtils.remove_entry(other, true) if other
  end

  def relative_file_dependencies
    file 'a/b/test.txt', "test\n"
    file 'a/b/sibling.txt', 'sibling one'
    file 'a/up.txt', 'up one'
    file 'content/a.html', 'a one'
    @absolute = File.realpath(Dir.mktmpdir)
    File.write(File.join(@absolute, 'abs.txt'), 'abs one')
    FileDependencyProcessor.files = [
      ['./sibling.txt', File.join(@path, 'a/b/sibling.txt')],
      ['../up.txt', File.join(@path, 'a/up.txt')],
      ['content/a.html', File.join(@content, 'a.html')],
      File.join(@absolute, 'abs.txt')
    ]
  end

  test 'relative file dependencies of a processor resolve against the source file or the load paths' do
    relative_file_dependencies
    in_other_directory do
      asset = new_env.find('a/b/test.txt')
      assert_equal [
        File.join(@path, 'a/b/sibling.txt'),
        File.join(@path, 'a/up.txt'),
        File.join(@content, 'a.html'),
        File.join(@absolute, 'abs.txt')
      ].sort, asset.file_dependency_paths.values.sort
      assert_equal File.join(@content, 'a.html'), asset.file_dependency_paths['content/a.html']
      assert_includes asset.file_dependencies, 'content/a.html'
      assert_includes asset.source, 'sibling.txt: sibling one'

      file 'a/b/sibling.txt', 'sibling two'
      assert_includes new_env.find('a/b/test.txt').export.source, 'sibling.txt: sibling two'
      file 'a/up.txt', 'up two'
      assert_includes new_env.find('a/b/test.txt').export.source, 'up.txt: up two'
      file 'content/a.html', 'a two'
      assert_includes new_env.find('a/b/test.txt').export.source, 'a.html: a two'
      File.write(File.join(@absolute, 'abs.txt'), 'abs two')
      assert_includes new_env.find('a/b/test.txt').export.source, 'abs.txt: abs two'
      assert_equal 5, FileDependencyProcessor.calls['a/b/test.txt']
    end
  ensure
    FileUtils.remove_entry(@absolute, true) if @absolute
  end

  test 'a relative file dependency of a processor is listened to' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'a/b/test.txt', "test\n"
    file 'a/b/sibling.txt', 'one'
    FileDependencyProcessor.files = [['./sibling.txt', File.join(@path, 'a/b/sibling.txt')]]

    in_other_directory do
      assert_includes @env.find('a/b/test.txt').source, 'sibling.txt: one'
      file 'a/b/sibling.txt', 'two'
      assert wait_until { @env.find('a/b/test.txt').source.include?('sibling.txt: two') }

      rm 'a/b/sibling.txt'
      assert wait_until { (@env.find('a/b/test.txt').source && false) rescue $!.is_a?(Condenser::FileNotFound) }
      file 'a/b/sibling.txt', 'three'
      assert wait_until { @env.find('a/b/test.txt').source.include?('sibling.txt: three') }
    end
  end

  test 'relative directory dependencies of a processor resolve against the source file or the load paths' do
    file 'a/b/test.txt', "test\n"
    file 'a/b/pages/a.html', 'a'
    file 'content/a.html', 'a'
    @second = File.realpath(Dir.mktmpdir)
    file 'shared/a.html', 'a', base: @second
    FileDependencyProcessor.directories = {
      ['./pages', File.join(@path, 'a/b/pages')] => { glob: '*.html' },
      ['content', @content] => { glob: '*.html' },
      ['shared', File.join(@second, 'shared')] => { glob: '*.html' }
    }

    in_other_directory do
      asset = new_env(@path, @second).find('a/b/test.txt')
      assert_equal [
        [File.join(@path, 'a/b/pages'), ['*.html'], false],
        ['content', ['*.html'], false],
        ['shared', ['*.html'], false]
      ].sort, asset.directory_dependencies.sort
      assert_equal({
        File.join(@path, 'a/b/pages') => File.join(@path, 'a/b/pages'),
        'content' => @content,
        'shared' => File.join(@second, 'shared')
      }, asset.directory_dependency_paths)

      file 'a/b/pages/b.html', 'b'
      assert_includes new_env(@path, @second).find('a/b/test.txt').export.source, 'pages: a.html,b.html'
      file 'content/b.html', 'b'
      assert_includes new_env(@path, @second).find('a/b/test.txt').export.source, 'content: a.html,b.html'
      file 'shared/b.html', 'b', base: @second
      assert_includes new_env(@path, @second).find('a/b/test.txt').export.source, 'shared: a.html,b.html'
      assert_equal 4, FileDependencyProcessor.calls['a/b/test.txt']
    end
  end

  test 'a missing relative directory dependency raises' do
    file 'a/b/test.txt', "test\n"
    file 'a/b/file', 'not a directory'
    FileDependencyProcessor.directories = { ['./file', File.join(@path, 'a/b')] => {} }

    in_other_directory do
      error = assert_raises(Condenser::FileNotFound) { new_env.find('a/b/test.txt').source }
      assert_equal "couldn't find directory './file' from #{File.join(@path, 'a/b/test.txt')}", error.message
    end
  end

  test 'relative paths for depend_on_file and depend_on_directory in a template' do
    file 'a/b/sibling.txt', 'sibling one'
    file 'a/up.txt', 'up one'
    file 'content/a.html', 'a one'
    file 'a/b/pages/a.html', 'a'
    @second = File.realpath(Dir.mktmpdir)
    file 'config/only.css', 'only one', base: @second
    file 'a/b/ctx.txt.erb', <<~ERB
      <% depend_on_file './sibling.txt' %><% depend_on_file '../up.txt' %><% depend_on_file 'content/a.html' %><% depend_on_file 'config/only.css' %><% depend_on_directory './pages', glob: '*.html' %><% depend_on_directory 'content', glob: '*.html', recursive: true %><%= %w(a/b/sibling.txt a/up.txt content/a.html).map { |f| File.read(File.join('#{@path}', f)) }.join(',') %>,<%= File.read('#{@second}/config/only.css') %>,<%= Dir.children('#{@path}/a/b/pages').sort.join(',') %>
    ERB

    in_other_directory do
      asset = new_env(@path, @second).find('a/b/ctx.txt')
      assert_includes asset.source, 'sibling one,up one,a one,only one,a.html'
      assert_equal [
        File.join(@path, 'a/b/sibling.txt'),
        File.join(@path, 'a/up.txt'),
        File.join(@content, 'a.html'),
        File.join(@second, 'config/only.css')
      ].sort, asset.file_dependency_paths.values.sort
      assert_equal [
        File.join(@path, 'a/b/sibling.txt'),
        File.join(@path, 'a/up.txt'),
        'config/only.css',
        'content/a.html'
      ].sort, asset.file_dependencies.sort
      assert_equal [
        [File.join(@path, 'a/b/pages'), ['*.html'], false],
        ['content', ['*.html'], true]
      ], asset.directory_dependencies
      assert_equal @content, asset.directory_dependency_paths['content']

      file 'a/b/sibling.txt', 'sibling two'
      assert_includes new_env(@path, @second).find('a/b/ctx.txt').export.source, 'sibling two'
      file 'a/up.txt', 'up two'
      assert_includes new_env(@path, @second).find('a/b/ctx.txt').export.source, 'up two'
      file 'content/a.html', 'a two'
      assert_includes new_env(@path, @second).find('a/b/ctx.txt').export.source, 'a two'
      file 'config/only.css', 'only two', base: @second
      assert_includes new_env(@path, @second).find('a/b/ctx.txt').export.source, 'only two'
      file 'a/b/pages/b.html', 'b'
      assert_includes new_env(@path, @second).find('a/b/ctx.txt').export.source, 'a.html,b.html'

      rm 'a/b/sibling.txt'
      error = assert_raises(Condenser::FileNotFound) { new_env(@path, @second).find('a/b/ctx.txt').source }
      assert_equal "couldn't find file './sibling.txt' from #{File.join(@path, 'a/b/ctx.txt.erb')}", error.message
    end
  end

  test 'depend_on_file and depend_on_directory raise for a missing relative path' do
    file 'config/tailwind.css', 'pwd'
    {
      "depend_on_file 'config/tailwind.css'" => "file 'config/tailwind.css'",
      "depend_on_file '../missing.txt'" => "file '../missing.txt'",
      "depend_on_directory './pages'" => "directory './pages'",
      "depend_on_directory 'pages'" => "directory 'pages'"
    }.each.with_index do |(helper, message), i|
      file "a/b/ctx#{i}.txt.erb", "<% #{helper} %>x"
      in_other_directory do |pwd|
        FileUtils.mkdir_p(File.join(pwd, 'pages'))
        file 'config/tailwind.css', 'pwd', base: pwd
        error = assert_raises(Condenser::FileNotFound) { new_env(File.join(@path, 'a')).find("b/ctx#{i}.txt").source }
        assert_equal "couldn't find #{message} from #{File.join(@path, "a/b/ctx#{i}.txt.erb")}", error.message
      end
    end
  end

  test 'a bare file dependency resolves against the first load path it is in' do
    @second = File.realpath(Dir.mktmpdir)
    file 'a/b/test.txt', "test\n"
    file 'config/only.css', 'only one', base: @second
    file 'config/both.css', 'first one'
    file 'config/both.css', 'second', base: @second
    FileDependencyProcessor.files = [
      ['config/only.css', File.join(@second, 'config/only.css')],
      ['config/both.css', File.join(@path, 'config/both.css')]
    ]

    in_other_directory do
      asset = new_env(@path, @second).find('a/b/test.txt')
      assert_equal({
        'config/both.css' => File.join(@path, 'config/both.css'),
        'config/only.css' => File.join(@second, 'config/only.css')
      }, asset.file_dependency_paths)

      file 'config/only.css', 'only two', base: @second
      assert_includes new_env(@path, @second).find('a/b/test.txt').export.source, 'only.css: only two'
      file 'config/both.css', 'first two'
      assert_includes new_env(@path, @second).find('a/b/test.txt').export.source, 'both.css: first two'
    end
  end

  test 'a bare file dependency that is only under base or Dir.pwd raises' do
    root = File.realpath(Dir.mktmpdir)
    file 'a/b/test.txt', "test\n"
    file 'config/tailwind.css', 'root', base: root
    FileDependencyProcessor.files = ['config/tailwind.css']

    in_other_directory do |pwd|
      file 'config/tailwind.css', 'pwd', base: pwd
      error = assert_raises(Condenser::FileNotFound) { new_env(base: root).find('a/b/test.txt').source }
      assert_equal "couldn't find file 'config/tailwind.css' from #{File.join(@path, 'a/b/test.txt')}", error.message
    end
  ensure
    FileUtils.remove_entry(root, true) if root
  end

  test 'a relative file dependency that is deleted invalidates the asset and the rebuild raises' do
    file 'a/b/test.txt', "test\n"
    file 'a/b/sibling.txt', 'one'
    FileDependencyProcessor.files = [['./sibling.txt', File.join(@path, 'a/b/sibling.txt')]]

    in_other_directory do
      assert_includes new_env.find('a/b/test.txt').export.source, 'sibling.txt: one'
      rm 'a/b/sibling.txt'
      error = assert_raises(Condenser::FileNotFound) { new_env.find('a/b/test.txt').export }
      assert_equal "couldn't find file './sibling.txt' from #{File.join(@path, 'a/b/test.txt')}", error.message

      file 'a/b/sibling.txt', 'two'
      assert_includes new_env.find('a/b/test.txt').export.source, 'sibling.txt: two'
    end
  end

  test 'a bare file dependency is shadowed by a file added to an earlier load path' do
    @second = File.realpath(Dir.mktmpdir)
    file 'config/x.txt', 'second', base: @second
    FileDependencyProcessor.files = [['config//./x.txt', :resolve]]

    in_other_directory do
      listening = new_env(@path, @second)
      assert_includes build(listening), 'x.txt: second'
      flush_listener(listening) if listening.build_cache.listening
      assert_equal ['config/x.txt'], listening.find('test.txt').file_dependencies
      assert_equal({ 'config/x.txt' => File.join(@second, 'config/x.txt') }, listening.find('test.txt').file_dependency_paths)

      file 'config/x.txt', 'first'
      assert wait_until { build(listening).include?('x.txt: first') } if listening.build_cache.listening
      assert_includes build(new_env(@path, @second)), 'x.txt: first'

      rm 'config/x.txt'
      assert wait_until { build(listening).include?('x.txt: second') } if listening.build_cache.listening
      assert_includes build(new_env(@path, @second)), 'x.txt: second'
    end
  end

  test 'a bare directory dependency is shadowed by a directory added to an earlier load path' do
    @second = File.realpath(Dir.mktmpdir)
    file 'pages/a.html', 'a', base: @second
    FileDependencyProcessor.directories = { ['pages', :resolve] => { glob: '*.html' } }

    in_other_directory do
      listening = new_env(@path, @second)
      assert_includes build(listening), 'pages: a.html'
      flush_listener(listening) if listening.build_cache.listening

      file 'pages/b.html', 'b'
      assert wait_until { build(listening).include?('pages: b.html') } if listening.build_cache.listening
      assert_includes build(new_env(@path, @second)), 'pages: b.html'

      FileUtils.rm_r(File.join(@path, 'pages'))
      assert wait_until { build(listening).include?('pages: a.html') } if listening.build_cache.listening
      assert_includes build(new_env(@path, @second)), 'pages: a.html'
    end
  end

  test 'a bare file dependency that is removed from every load path raises when rebuilt' do
    file 'config/x.txt', 'one'
    FileDependencyProcessor.files = [['config/x.txt', :resolve]]

    in_other_directory do
      listening = new_env
      assert_includes build(listening), 'x.txt: one'
      flush_listener(listening) if listening.build_cache.listening

      rm 'config/x.txt'
      assert_equal({ 'config/x.txt' => nil }, new_env.find('test.txt').file_dependency_paths)
      assert wait_until { raises_not_found?(listening) } if listening.build_cache.listening
      error = assert_raises(Condenser::FileNotFound) { build(new_env) }
      assert_equal "couldn't find file 'config/x.txt' from #{File.join(@path, 'test.txt')}", error.message
    end
  end

  test 'a missing absolute file or directory dependency raises' do
    FileDependencyProcessor.files = [File.join(@content, 'missing.html')]
    error = assert_raises(Condenser::FileNotFound) { build(new_env) }
    assert_equal "couldn't find file '#{File.join(@content, 'missing.html')}' from #{File.join(@path, 'test.txt')}", error.message

    FileDependencyProcessor.files = []
    FileDependencyProcessor.directories = { File.join(@path, 'missing') => {} }
    error = assert_raises(Condenser::FileNotFound) { build(new_env) }
    assert_equal "couldn't find directory '#{File.join(@path, 'missing')}' from #{File.join(@path, 'test.txt')}", error.message
  end

  test 'a rebuild stats and records each file dependency once' do
    file 'content/a.html', 'one'
    path = File.join(@content, 'a.html')
    FileDependencyProcessor.files = [path]
    asset = @env.find('test.txt')
    assert_includes asset.source, 'a.html: one'

    file 'content/a.html', 'two'
    asset.needs_reprocessing!
    stats = Thread.current[:stats] = Hash.new(0)
    real_paths = Thread.current[:real_paths] = Hash.new(0)
    assert_includes @env.find('test.txt').source, 'a.html: two'
    assert_equal 1, stats[path]
    assert_equal (@env.build_cache.listening ? 1 : 0), real_paths[path]
  ensure
    Thread.current[:stats] = Thread.current[:real_paths] = nil
  end

  test 'a file is digested once per build' do
    file 'content/a.html', 'one'
    path = File.join(@content, 'a.html')

    first, second = @env.build do
      digest = @env.build_cache.file_digest(path)
      File.write(path, 'two, which is longer')
      [digest, @env.build_cache.file_digest(path)]
    end
    assert_equal first, second
    assert_not_equal first, @env.build_cache.file_digest(path)
  end

  test 'a build that raises while starting still lets the next build start' do
    file 'content/a.html', 'one'
    path = File.join(@content, 'a.html')

    @env.build_cache.stubs(:clear_if_npm_changed).raises(Errno::EACCES).then.returns(nil)
    assert_raises(Errno::EACCES) { @env.build { } }

    first = @env.build { @env.build_cache.file_digest(path) }
    File.write(path, 'two, which is longer')
    assert_not_equal first, @env.build { @env.build_cache.file_digest(path) }
  end

  test 'a dependency path is looked up once per build, and ./ paths for each source directory' do
    @second = File.realpath(Dir.mktmpdir)
    file 'config/x.txt', 'second', base: @second
    file 'a/x.txt', 'a'
    file 'b/x.txt', 'b'
    @env.append_path(@second)

    @env.build do
      assert_equal File.join(@second, 'config/x.txt'), @env.expand_dependency_path('config/x.txt')
      file 'config/x.txt', 'first'
      assert_equal File.join(@second, 'config/x.txt'), @env.expand_dependency_path('config/x.txt')
      assert_equal File.join(@path, 'a/x.txt'), @env.expand_dependency_path('./x.txt', source_file: File.join(@path, 'a/test.txt'))
      assert_equal File.join(@path, 'b/x.txt'), @env.expand_dependency_path('./x.txt', source_file: File.join(@path, 'b/test.txt'))
    end
    assert_equal File.join(@path, 'config/x.txt'), @env.expand_dependency_path('config/x.txt')
  end

  test 'a dependency path is looked up again when the load paths change during a build' do
    @second = File.realpath(Dir.mktmpdir)
    file 'config/x.txt', 'second', base: @second
    file 'config/x.txt', 'first'

    @env.build do
      assert_equal File.join(@path, 'config/x.txt'), @env.expand_dependency_path('config/x.txt')
      @env.prepend_path(@second)
      assert_equal File.join(@second, 'config/x.txt'), @env.expand_dependency_path('config/x.txt')
    end
  end

  test 'a file dependency through a symlink that is retargeted is listened to at its new path after a rebuild' do
    skip 'needs a listener' if !@env.build_cache.listening
    @second = File.realpath(Dir.mktmpdir)
    @env.watch(@second)
    file 'one/a.html', 'one', base: @second
    file 'two/a.html', 'two', base: @second
    link = File.join(@content, 'link')
    File.symlink(File.join(@second, 'one'), link)
    FileDependencyProcessor.files = [File.join(link, 'a.html')]
    asset = @env.find('test.txt')
    assert_includes asset.source, 'a.html: one'

    File.delete(link)
    File.symlink(File.join(@second, 'two'), link)
    asset.needs_reprocessing!
    assert_includes @env.find('test.txt').source, 'a.html: two'

    file 'two/a.html', 'three', base: @second
    assert_rebuilds_with 'a.html: three'
  end

  test 'expand_dependency_path needs a source file for ./ and ../ paths' do
    file 'x.txt', 'x'
    ['./x.txt', '../x.txt', '.', '..'].each do |path|
      error = assert_raises(ArgumentError) { @env.expand_dependency_path(path) }
      assert_equal "the dependency path '#{path}' is relative to a source file, it needs source_file:", error.message
    end
    assert_equal File.join(@path, 'x.txt'), @env.expand_dependency_path('./x.txt', source_file: File.join(@path, 'test.txt'))
  end

end
