require 'test_helper'

class EnvironmentTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.clear_path
  end
  
  test "default logger level is set to warn" do
    assert_equal Logger::WARN, @env.logger.level
  end

  test "paths" do
    assert_equal [], @env.path
  end
  
  test "prepend_path" do
    Dir.mkdir(File.join(@path, 'a'))
    Dir.mkdir(File.join(@path, 'b'))
    
    assert_equal [], @env.path
    @env.prepend_path File.join(@path, 'a')
    @env.prepend_path File.join(@path, 'b')
    assert_equal ['b', 'a'].map { |d| File.expand_path(d, @path) }, @env.path
  end
  
  test "append_path" do
    Dir.mkdir(File.join(@path, 'a'))
    Dir.mkdir(File.join(@path, 'b'))
    
    assert_equal [], @env.path
    @env.append_path File.join(@path, 'a')
    @env.append_path File.join(@path, 'b')
    assert_equal ['a', 'b'].map { |d| File.expand_path(d, @path) }, @env.path
  end
  
  test "clear_path" do
    Dir.mkdir(File.join(@path, 'a'))
    
    @env.prepend_path File.join(@path, 'a')
    assert_not_empty @env.path
    @env.clear_path
    assert_empty @env.path
  end

  test "digestor=" do
    assert_equal @env.digestor, Digest::SHA256
    @env.digestor = Digest::MD5
    assert_equal @env.digestor, Digest::MD5
  end
  
end
