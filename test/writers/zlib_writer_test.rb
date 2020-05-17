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
  
end