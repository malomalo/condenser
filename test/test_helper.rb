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

require "active_support"
require "active_support/testing/autorun"
require 'mocha/setup'
require 'minitest/reporters'

# This is because Rails changed it's minitest intergration, not sure whats
# up here
Minitest.load_plugins
Minitest.extensions.delete('rails')
Minitest.extensions.unshift('rails')

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

class ActiveSupport::TestCase

  def setup
    @path = Dir.mktmpdir
    @env = Condenser.new(@path)
    @env.context_class.class_eval do
      def asset_path(path, options = {})
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
  
  def file(name, source)
    FileUtils.mkdir_p(File.join(@path, File.dirname(name)))
    File.write(File.join(@path, name), source)
  end
  
  def assert_file(path, mime_types, source=nil)
    asset = @env.find(path)
    assert asset, "Couldn't find asset \"#{path}\""
    asset.process
    assert_equal path,                        asset.filename
    assert_equal Array(mime_types),           asset.content_types
    assert_equal(source.rstrip, asset.source.rstrip) if !source.nil?
  end
  
  def assert_exported_file(path, mime_types, source=nil)
    asset = @env.find(path)
    assert asset, "Couldn't find asset \"#{path}\""
    asset = asset.export
    assert_equal path,                        asset.filename
    assert_equal Array(mime_types),           asset.content_types
    assert_equal(source.rstrip, asset.source.rstrip) if !source.nil?
  end

end
