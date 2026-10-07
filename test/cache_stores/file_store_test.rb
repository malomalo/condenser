require 'test_helper'
require 'open3'

class CacheFileStoreTest < ActiveSupport::TestCase
  
  def setup
    super
    @cachepath = Dir.mktmpdir
    @env.cache = Condenser::Cache::FileStore.new(@cachepath)
  end
  
  def teardown
    super
    FileUtils.remove_entry(@cachepath, true)
  end

  test 'reading from a populated cache store' do
    file 'test.txt.erb', "1<%= 1 + 1 %>3\n"
    
    assert_file 'test.txt', 'text/plain', <<~CSS
    123
    CSS

    oldenv = @env
    begin
      @env = Condenser.new(@path, base: @path)
      @env.cache = Condenser::Cache::FileStore.new(@cachepath)
      Condenser::Erubi.stubs(:call).never

      assert_file 'test.txt', 'text/plain', <<~CSS
      123
      CSS
    ensure
      @env = oldenv
    end
  end

  test "works when nothing else has loaded zlib" do
    script = <<~SCRIPT
      require "condenser"
      store = Condenser::Cache::FileStore.new(ARGV[0])
      store.set("key", { "a" => 1 })
      print store.get("key").inspect
    SCRIPT

    output, status = Open3.capture2e(RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", script, @cachepath)
    assert status.success?, output
    assert_equal({ "a" => 1 }.inspect, output.lines.last)
  end

end
