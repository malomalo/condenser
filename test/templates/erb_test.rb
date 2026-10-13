require 'test_helper'

class CondenserErubiTest < ActiveSupport::TestCase

  # Records the asset as a plain path, like condenser-rails'
  # compute_asset_path.
  module RecordingAssetPath
    def asset_path(path, options = {})
      asset = environment.find!(path)
      @dependencies << asset.source_file
      "/assets/#{asset.path}"
    end
  end

  def setup
    super
    @env.context_class.prepend(RecordingAssetPath)
  end

  def teardown
    super
    FileUtils.remove_entry(@cache_dir, true) if @cache_dir
  end

  def new_env
    @cache_dir ||= File.realpath(Dir.mktmpdir)
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, cache: Condenser::Cache::FileStore.new(@cache_dir))
    env.unregister_writer(Condenser::ZlibWriter)
    env.unregister_writer(Condenser::BrotliWriter)
    env.context_class.prepend(RecordingAssetPath)
    env
  end

  test 'find' do
    file 'test.js.erb', "1<%= 1 + 1 %>3\n"
    
    assert_file 'test.js', 'application/javascript', <<~CSS
    123
    CSS
  end

  test 'asset_path makes a new process reprocess the template when the asset changes' do
    file 'logo.png', 'one'
    file 'test.js.erb', "console.log('<%= asset_path('logo.png') %>');\n"

    source = new_env.find('test.js').source
    assert_includes source, new_env.find('logo.png').path
    assert_equal ['logo.png'], new_env.find('test.js').process_dependencies.map(&:filename)

    file 'logo.png', 'two'
    env = new_env
    assert_not_equal source, env.find('test.js').source
    assert_includes env.find('test.js').source, env.find('logo.png').path
  end

  test 'asset_path makes the listener reprocess the template when the asset changes' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'logo.png', 'one'
    file 'test.js.erb', "console.log('<%= asset_path('logo.png') %>');\n"

    source = @env.find('test.js').source
    file 'logo.png', 'two'
    assert wait_until { @env.find('test.js').source != source }
    assert_includes @env.find('test.js').source, @env.find('logo.png').path
  end

  test 'asset_data_uri depends on the asset' do
    file 'logo.png', 'one'
    file 'test.txt.erb', "<%= asset_data_uri('logo.png') %>\n"

    assert_includes new_env.find('test.txt').source, 'data:image/png;base64,b25l'
    file 'logo.png', 'two'
    assert_includes new_env.find('test.txt').source, 'data:image/png;base64,dHdv'
  end

  test 'depend_on invalidates the template when the dependency changes' do
    file 'other.js', "console.log(1);\n"
    file 'test.js.erb', "<% depend_on('other.js') %>console.log(<%= File.read('#{@path}/other.js').length %>);\n"

    assert_includes new_env.find('test.js').source, 'console.log(16)'
    file 'other.js', "console.log(100);\n"
    assert_includes new_env.find('test.js').source, 'console.log(18)'
  end

  test 'depend_on is relative to the template' do
    file 'dir/other.js', "console.log(1);\n"
    file 'dir/test.js.erb', "<% depend_on('./other.js') %>console.log(2);\n"

    assert_equal ['dir/other.js'], @env.find('dir/test.js').process_dependencies.map(&:filename)
  end

  test 'depend_on_env invalidates the template when the variable changes' do
    ENV['CONDENSER_ERB_TEST'] = 'one'
    file 'test.txt.erb', "<% depend_on_env('CONDENSER_ERB_TEST') %><%= ENV['CONDENSER_ERB_TEST'] %>\n"

    assert_equal "one\n", new_env.find('test.txt').source
    assert_equal ['CONDENSER_ERB_TEST'], new_env.find('test.txt').env_dependencies
    assert_equal [], new_env.find('test.txt').process_dependencies

    ENV['CONDENSER_ERB_TEST'] = 'two'
    assert_equal "two\n", new_env.find('test.txt').source
  ensure
    ENV.delete('CONDENSER_ERB_TEST')
  end

  test 'env_proxy depends on the variable it reads' do
    ENV['CONDENSER_ERB_TEST'] = 'one'
    file 'test.txt.erb', "<%= env_proxy['CONDENSER_ERB_TEST'] %>\n"

    assert_equal "one\n", new_env.find('test.txt').source
    ENV['CONDENSER_ERB_TEST'] = 'two'
    assert_equal "two\n", new_env.find('test.txt').source
  ensure
    ENV.delete('CONDENSER_ERB_TEST')
  end

  test 'link_asset adds a linked asset that the manifest compiles' do
    file 'img.png', 'png'
    file 'test.js.erb', "<% link_asset('img.png') %>console.log(1);\n"

    asset = @env.find('test.js')
    assert_equal ['img.png'], asset.linked_assets.map(&:filename)
    assert_nil @env.new_context_class.link_asset('img.png')

    dir = Dir.mktmpdir
    Condenser::Manifest.new(@env, File.join(dir, 'manifest.json')).compile('test.js')
    manifest = JSON.parse(File.read(File.join(dir, 'manifest.json')))
    assert_equal ['img.png', 'test.js'], manifest.keys.sort
    assert File.exist?(File.join(dir, @env.find('img.png').path))
  ensure
    FileUtils.remove_entry(dir, true) if dir
  end

  test 'link_asset raises when the asset is missing' do
    file 'test.js.erb', "<% link_asset('missing.png') %>console.log(1);\n"

    error = assert_raises(Condenser::FileNotFound) { @env.find('test.js').source }
    assert_includes error.message, "'missing.png'"
    assert_includes error.message, File.join(@path, 'test.js.erb')
  end

  test 'link_asset and depend_on_asset are relative to the template' do
    file 'sibling.png', 'top'
    file 'dir/sibling.png', 'dir'
    file 'dir/other.png', 'other'
    file 'dir/test.txt.erb', "<% link_asset('./sibling.png') %><%= depend_on_asset('./other.png').source %>\n"

    asset = @env.find('dir/test.txt')
    assert_equal "other\n", asset.source
    assert_equal ['dir/sibling.png'], asset.linked_assets.map(&:filename)
    assert_equal ['dir/other.png', 'dir/sibling.png'], asset.process_dependencies.map(&:filename).sort
  end

end
