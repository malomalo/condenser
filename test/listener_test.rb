require 'test_helper'

class ListenerTest < ActiveSupport::TestCase

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


end
