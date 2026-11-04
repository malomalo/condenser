require 'test_helper'

class ZlibWriterTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.clear_pipeline
    @env.register_writer Condenser::ZlibWriter.new
  end
  
  test 'writes a compressed file' do
    data = "console.log('hello world!');"

    file 'index.js', data
    Dir.mktmpdir do |dir|
      @env.find_export('index.js').write(dir)
      filename = "index-#{Digest::SHA256.hexdigest(data)}.js.gz"
      assert_equal [filename], Dir.children(dir)
      Zlib::GzipReader.open(File.join(dir, filename)) do |gz|
        assert_equal data, gz.read
      end
    end
  end

  test 'skips by its own extension, independently of the other writers' do
    @env.register_writer Condenser::FileWriter.new
    file 'index.js', "console.log('hello world!');"
    export = @env.find_export('index.js')

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "#{export.path}.gz"), 'existing')
      assert_equal [export.path], export.write(dir)
      assert_equal 'existing', File.read(File.join(dir, "#{export.path}.gz"))
      assert_equal export.source, File.read(File.join(dir, export.path))
    end

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, export.path), 'existing')
      assert_equal ["#{export.path}.gz"], export.write(dir)
      assert_equal 'existing', File.read(File.join(dir, export.path))
      Zlib::GzipReader.open(File.join(dir, "#{export.path}.gz")) { |gz| assert_equal export.source, gz.read }
    end
  end
  
end