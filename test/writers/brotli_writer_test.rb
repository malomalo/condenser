require 'test_helper'

class BrotliWriterTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.clear_pipeline
    @env.register_writer Condenser::BrotliWriter.new
  end
  
  test 'writes a compressed file' do
    data = "console.log('hello world!');"

    file 'index.js', data
    Dir.mktmpdir do |dir|
      @env.find_export('index.js').write(dir)
      filename = "index-#{Digest::SHA256.hexdigest(data)}.js.br"
      assert_equal [filename], Dir.children(dir)
      puts File.read(File.join(dir, filename)).inspect
      assert_equal data, Brotli.inflate(File.read(File.join(dir, filename)))
    end
  end
  
end