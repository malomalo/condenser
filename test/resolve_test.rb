require 'test_helper'

class ResolveTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.clear_pipeline
    @env.clear_path
    @env.append_path(@path)
    @env.register_template    'application/erb', Condenser::Erubi
    @env.register_transformer 'text/scss', 'text/css', Condenser::Erubi
    @env.register_exporter    'application/javascript', Condenser::RollupProcessor
    @env.register_writer      Condenser::ZlibWriter.new(mime_types: 'application/javascript')
  end
  
  test 'decompose_path' do
    assert_equal [nil, 'test', ['.text'], ['text/plain']], @env.decompose_path('test.text')
    
    assert_equal ['dir', 'test', ['.text'], ['text/plain']], @env.decompose_path('dir/test.text')
    
    assert_equal ['dir', 'test.unkownmime', ['.text'], ['text/plain']], @env.decompose_path('dir/test.unkownmime.text')
    
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
  
  test 'relative require' do
    file 'a/main.js', <<~JS
      import { cube } from './math.js';
      console.log( cube( 5 ) ); // 125
    JS
    file 'a/math.js', <<~JS
      export function cube ( x ) {
        return x * x * x;
      }
    JS

    file 'b/math.js', <<~JS
      export function square ( x ) {
        return x * x;
      }
    JS

    @env.append_path File.join(@path, 'b')
    @env.append_path File.join(@path, 'a')

    
    assert_exported_file('main.js', 'application/javascript', <<~JS)
      (function () {
        'use strict';

        function cube ( x ) {
          return x * x * x;
        }

        console.log( cube( 5 ) ); // 125

      }());
    JS
  end
  
  test 'resolve! raises NotFound' do
    assert_raises Condenser::FileNotFound do
      @env.resolve!('**/*')
    end
  end
  
  test 'resolve a file with a / as the prefix' do
    file 'file.js', 'test'
    
    assert_file('/file.js', 'application/javascript')
  end
  
  test 'resolve a file.*' do
    file 'file.js', 'console.log(1);'
    file 'file.scss', 'body { background: red; }'
    file 'test/file.scss', 'body { background: green; }'

    assert_equal %w(file.js file.scss), @env.resolve('file.*').map(&:filename)
    assert_equal %w(file.css file.js),  @env.resolve('file.*', accept: ['text/css', 'application/javascript']).map(&:filename)

    assert_equal %w(file.js file.scss test/file.scss), @env.resolve('**/file.*').map(&:filename)
    assert_equal %w(file.css file.js test/file.css), @env.resolve('**/file.*', accept: ['text/css', 'application/javascript']).map(&:filename)
  end
  
end
