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
      assert_equal data, Brotli.inflate(File.read(File.join(dir, filename)))
    end
  end

  test 'compresses text, fonts and other types in their mode' do
    writer = Condenser::BrotliWriter.new
    assert_equal :text, writer.mode_for_mime_type('application/javascript')
    assert_equal :font, writer.mode_for_mime_type('font/otf')
    assert_equal :generic, writer.mode_for_mime_type('image/x-icon')

    Brotli::Writer.expects(:new).with(anything, mode: :text, quality: 11).returns(stub(write: nil, finish: nil))
    file 'index.js', "console.log('hello world!');"
    Dir.mktmpdir { |dir| @env.find_export('index.js').write(dir) }
  end
  
end