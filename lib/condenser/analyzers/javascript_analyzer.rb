require 'json'
require File.expand_path('../../processors/node_processor', __FILE__)

class Condenser
  class JavascriptAnalyzer < NodeProcessor
    class Error < StandardError; end
    
    def self.call(environment, input)
      new.call(environment, input)
    end
    
    def initialize(options = {})
      @options = options.merge({
        ast: false,
        sourceMap: false
      }).freeze
    end

    def call(environment, input)
      opts = {
        'filename' => input[:filename],
        'moduleId' => input[:filename].sub(/(\..+)+/, ''),
        'filenameRelative' => input[:filename],
      }.merge(@options)
      
      result = exec_runtime(<<-JS)
        module.paths.push("#{File.expand_path('../../processors/node_modules', __FILE__)}")
      
        const babel = require('@babel/core');
        const source = #{JSON.generate(input[:source])};
        const options = #{JSON.generate(opts)};
        let imports = [];
        
        options['plugins'] = [];
        options['plugins'].push(function({ types: t }) {
          return {
            visitor: {
              ImportDeclaration(path, state) {
                imports.push(path.node.source.value);
              }
            }
          };
        });
        
        try {
          const result = babel.transform(source, options);
          console.log(JSON.stringify({imports: imports}));
        } catch(e) {
          console.log(JSON.stringify({'error': e.name + ": " + e.message}));
          process.exit(1);
        }
      JS
      
      if result['error']
        raise Error, result['error']
      else
        result['imports'].each do |i|
          input[:dependencies] << i
        end
      end
    end
  
  end
end