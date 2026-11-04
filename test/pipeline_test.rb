require 'test_helper'

class PipelineTest < ActiveSupport::TestCase
  
  class Writer
    
    def mime_types
      ['*/*']
    end
    
  end
  
  def setup
    super
    @env.clear_pipeline
  end
  
  test 'clear_pipeline' do
    processor = Condenser::Processor.new
    @env.register_mime_type      'application/javascript', extension: 'js', charset: :unicode
    @env.register_template       'application/erb', processor
    @env.register_preprocessor   'application/javascript', processor
    @env.register_transformer    'application/scss', 'application/css', processor
    @env.register_postprocessor  'application/javascript', processor
    @env.register_minifier       'application/javascript', processor
    @env.register_writer         PipelineTest::Writer.new

    vars = %w(templates preprocessors transformers postprocessors minifiers writers)
    vars.each do |var|
      assert_not_empty @env.send(var)
    end
    
    @env.clear_pipeline
    
    vars.each do |var|
      assert_empty @env.send(var)
    end
  end
  
  test 'unregister_writer removes a writer class or instance for every mime type' do
    file_writer = Condenser::FileWriter.new
    zlib_writer = Condenser::ZlibWriter.new
    @env.register_writer file_writer
    @env.register_writer zlib_writer
    @env.register_writer Condenser::BrotliWriter.new

    @env.unregister_writer(Condenser::BrotliWriter)
    assert_equal [file_writer, zlib_writer], @env.writers_for_mime_type('application/javascript')

    @env.unregister_writer(zlib_writer)
    assert_equal [file_writer], @env.writers_for_mime_type('application/javascript')
  end

  test 'with no writer for a mime type, nothing is written' do
    @env.unregister_writer(Condenser::FileWriter)
    assert_equal [], @env.writers_for_mime_type('application/javascript')

    file 'main.js', "console.log(1);"
    Dir.mktmpdir do |dir|
      assert_equal [], @env.find_export('main.js').write(dir)
      assert_empty Dir.children(dir)
    end
  end

  test 'register_writer raises for a writer class' do
    error = assert_raises(ArgumentError) { @env.register_writer(Condenser::ZlibWriter) }
    assert_equal 'Condenser::ZlibWriter is a class, register Condenser::ZlibWriter.new', error.message
  end

  test 'unregister_writer with FileWriter leaves the writers that subclass it' do
    zlib_writer = Condenser::ZlibWriter.new
    @env.register_writer Condenser::FileWriter.new
    @env.register_writer zlib_writer

    @env.unregister_writer(Condenser::FileWriter)
    assert_equal [zlib_writer], @env.writers_for_mime_type('application/javascript')
  end

end
