require 'test_helper'

class ResolveTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.clear_pipeline
    @env.register_template  'application/erb', Condenser::Erubi
    @env.register_transformer 'text/scss', 'text/css', Condenser::Erubi
    @env.register_writer 'application/javascript', Condenser::Erubi, 'application/gzip'
  end
  
  test 'decompose_path' do
    assert_equal [nil, 'test', ['.text'], ['text/plain']], @env.decompose_path('test.text')
    
    assert_equal ['dir', 'test', ['.text'], ['text/plain']], @env.decompose_path('dir/test.text')
    
    assert_equal [nil, '*', nil, []], @env.decompose_path('*')
    assert_equal ['*', '*', nil, []], @env.decompose_path('*/*')
    assert_equal ['**', '*', nil, []], @env.decompose_path('**/*')
    
    assert_equal ['test', '*', nil, []], @env.decompose_path('test/*')
    assert_equal ['test/*', '*', nil, []], @env.decompose_path('test/*/*')
    assert_equal ['test/**', '*', nil, []], @env.decompose_path('test/**/*')
    
    assert_equal [nil, '*', ['.js'], ['application/javascript']], @env.decompose_path('*.js')
    assert_equal ['*', '*', ['.js'], ['application/javascript']], @env.decompose_path('*/*.js')
    assert_equal ['**', '*', ['.js'], ['application/javascript']], @env.decompose_path('**/*.js')
    
    assert_equal ['test', '*', ['.js'], ['application/javascript']], @env.decompose_path('test/*.js')
    assert_equal ['test/*', '*', ['.js'], ['application/javascript']], @env.decompose_path('test/*/*.js')
    assert_equal ['test/**', '*', ['.js'], ['application/javascript']], @env.decompose_path('test/**/*.js')
  end
  
  test 'resolve' do
    file 'file.js', 'test'
    file 'test/file.scss', 'test'
    file 'test/z/file.js', 'test'
    
    assert_file('file.js', 'application/javascript')
    assert_file('test/file.css', 'text/css')
    
    assert_equal %w(file.js test/file.scss test/z/file.js), @env.resolve('**/*').map(&:filename)
    assert_equal %w(file.js test/file.css test/z/file.js), @env.resolve('**/*', accept: ['text/css', 'application/javascript']).map(&:filename)
    assert_equal %w(file.js), @env.resolve('*', accept: ['application/javascript']).map(&:filename)
    assert_equal %w(file.js test/z/file.js), @env.resolve('**/*', accept: ['application/javascript']).map(&:filename)
    assert_equal %w(file.js), @env.resolve('*.js').map(&:filename)
    assert_equal %w(file.js test/z/file.js), @env.resolve('**/*.js').map(&:filename)

    
    assert_equal %w(test/file.scss), @env.resolve('test/*').map(&:filename)
    assert_equal %w(test/file.css), @env.resolve('test/*', accept: ['text/css', 'application/javascript']).map(&:filename)
    assert_equal %w(test/file.scss test/z/file.js), @env.resolve('test/**/*').map(&:filename)
    assert_equal %w(test/file.css test/z/file.js), @env.resolve('test/**/*', accept: ['text/css', 'application/javascript']).map(&:filename)
    assert_equal %w(test/z/file.js), @env.resolve('test/z/*', accept: ['application/javascript']).map(&:filename)
    assert_equal %w(test/z/file.js), @env.resolve('test/**/*', accept: ['application/javascript']).map(&:filename)
    assert_equal %w(test/z/file.js), @env.resolve('test/z/*.js').map(&:filename)
    assert_equal %w(test/z/file.js), @env.resolve('test/**/*.js').map(&:filename)
  end
  
  test 'resolve! raises NotFound' do
    assert_raises Condenser::FileNotFound do
      @env.resolve!('**/*')
    end
  end
  
end
