require 'test_helper'

class PipelineTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.clear_pipeline
  end
  
  test 'clear_pipeline' do
    @env.register_mime_type      'application/javascript', extension: 'js', charset: :unicode
    @env.register_template       'application/erb', PipelineTest
    @env.register_preprocessor   'application/javascript', PipelineTest
    @env.register_transformer    'application/scss', 'application/css', PipelineTest
    @env.register_postprocessor  'application/javascript', PipelineTest
    @env.register_minifier       'application/javascript', PipelineTest
    @env.register_writer         '*/*', PipelineTest

    vars = %w(templates preprocessors transformers postprocessors minifiers writers)
    vars.each do |var|
      assert_not_empty @env.send(var)
    end
    
    @env.clear_pipeline
    
    vars.each do |var|
      assert_empty @env.send(var)
    end
  end
  
end
