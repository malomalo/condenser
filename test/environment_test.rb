require 'test_helper'

class EnvironmentTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.clear_path
  end
  
  test "working directory is the default root" do
    assert_equal Dir.pwd, Condenser.new.root
  end

  test "default logger level is set to warn" do
    assert_equal Logger::WARN, @env.logger.level
  end

  test "paths" do
    assert_equal [], @env.path
  end
  
  test "prepend_path" do
    assert_equal [], @env.path
    @env.prepend_path 'a'
    @env.prepend_path 'b'
    assert_equal ['b', 'a'].map { |d| File.expand_path(d, @path) }, @env.path
  end
  
  test "append_path" do
    assert_equal [], @env.path
    @env.append_path 'a'
    @env.append_path 'b'
    assert_equal ['a', 'b'].map { |d| File.expand_path(d, @path) }, @env.path
  end
  
  test "clear_path" do
    @env.append_path 'a'
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
