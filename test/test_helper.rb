# To make testing/debugging easier, test within this source tree versus an
# installed gem
$LOAD_PATH << File.expand_path('../lib', __FILE__)

require 'simplecov'
SimpleCov.start do
  add_group 'lib', 'condenser/lib'
  add_group 'ext', 'condenser/ext'
end

require 'fileutils'

require 'condenser'
require 'condenser/server'
require 'condenser/cache/memory_store'

require 'byebug'
require "active_support"
require "active_support/testing/autorun"
require 'mocha/minitest'
require 'minitest/reporters'

# This is because Rails changed it's minitest intergration, not sure whats
# up here
Minitest.load_plugins
Minitest.extensions.delete('rails')
Minitest.extensions.unshift('rails')

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

class ActiveSupport::TestCase

  def setup
    @path = File.realpath(Dir.mktmpdir)
    @npm_dir = File.expand_path('../../tmp', __FILE__)
    Dir.mkdir(@npm_dir) if !Dir.exist?(@npm_dir)
    @env = Condenser.new(@path, logger: Logger.new('/dev/null', level: :debug), npm_path: @npm_dir, base: @path)
    @env.unregister_writer(Condenser::ZlibWriter)
    @env.unregister_writer(Condenser::BrotliWriter)
    @env.context_class.class_eval do
      def asset_path(path, options = {})
        path = environment.find!(path, options).path
        "/assets/#{path}"
      end
    end
  end

  def teardown
    FileUtils.remove_entry(@path, true)
  end
  
  def assert_json(json, &block)
    assert_equal json, jbuild(&block)
  end
  
  def file(name, source, base: nil)
    base ||= @path
    dir = name.include?('/') ? File.join(base, File.dirname(name)) : base
    path = File.join(base, name)
    
    FileUtils.mkdir_p(dir)
    if File.exist?(path)
      stat = Time.now.to_f - File.stat(path).mtime.to_f
      sleep(1 - stat) if stat < 1
    end
    File.write(path, source)
    sleep 0.25 if @env.build_cache.listening
  end
  
  def rm(name)
    File.delete(File.join(@path, name))
  end
  
  def assert_file(path, mime_types, source=nil)
    sleep 0.25 if @env.build_cache.listening
    asset = @env.find(path)
    assert asset, "Couldn't find asset \"#{path}\""
    asset.process
    assert_equal path.delete_prefix('/'),     asset.filename
    assert_equal Array(mime_types),           asset.content_types
    assert_equal(source.rstrip, asset.source.rstrip) if !source.nil?
    asset
  end
  
  def assert_exported_file(path, mime_types, source=nil)
    sleep 0.25 if @env.build_cache.listening
    asset = @env.find(path)
    assert asset, "Couldn't find asset \"#{path}\""
    asset = asset.export
    assert_equal path,                        asset.filename
    assert_equal Array(mime_types),           asset.content_types
    assert_equal(source.rstrip, asset.source.rstrip) if !source.nil?
    asset
  end

end
