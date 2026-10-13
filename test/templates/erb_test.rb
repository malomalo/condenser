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

  test 'link_asset adds a linked asset that the manifest compiles' do
    file 'img.png', 'png'
    file 'test.js.erb', "<% link_asset('img.png') %>console.log(1);\n"

    asset = @env.find('test.js')
    assert_equal ['img.png'], asset.linked_assets.map(&:filename)
    assert_equal @env.find('img.png'), asset.environment.new_context_class.link_asset('img.png')

    dir = Dir.mktmpdir
    Condenser::Manifest.new(@env, File.join(dir, 'manifest.json')).compile('test.js')
    manifest = JSON.parse(File.read(File.join(dir, 'manifest.json')))
    assert_equal ['img.png', 'test.js'], manifest.keys.sort
    assert File.exist?(File.join(dir, @env.find('img.png').path))
  ensure
    FileUtils.remove_entry(dir, true) if dir
  end

end
