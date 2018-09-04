require 'ejs'

class Condenser
  class EjsTransformer < NodeProcessor
    
    STRICT = true

    def self.call(environment, input)
      new.call(environment, input)
    end

    def call(environment, input)
      input[:source] = ::EJS.transform(input[:source], {strict: STRICT})
      
      if STRICT
        opts = {
          # 'moduleRoot' => nil,
          'filename' => input[:filename],
          'moduleId' => input[:filename].sub(/(\..+)+/, ''),
          'cwd' => '/assets/',
          'filenameRelative' => input[:filename],#split_subpath(input[:load_path], input[:filename]),
          'sourceFileName' => input[:filename],
          # 'sourceMapTarget' => input[:filename]
          # 'inputSourceMap'
          ast: false,
          compact: false,
          sourceMap: true,
          plugins: []
        }
  
        result = exec_runtime(<<-JS)
          module.paths.push("#{File.expand_path('../../processors/node_modules', __FILE__)}")
  
          const babel = require('@babel/core');
          const source = #{JSON.generate(input[:source])};
          const options = #{JSON.generate(opts)};

          function globalVar(scope, name) {
            if (name in scope.globals) {
              return true;
            } else if (scope.parent === null) {
              return false;
            } else {
              return globalVar(scope.parent, name);
            }
          }
    
          options['plugins'].push(function({ types: t }) {
            return {
              visitor: {
                Identifier(path, state) {
                  if ( path.parent.type == 'MemberExpression' && path.parent.object != path.node) {
                    return;
                  }

                  if (globalVar(path.scope, path.node.name) && !(path.node.name in global)) {
                    path.replaceWith(
                      t.memberExpression(t.identifier("locals"), path.node)
                    );
                  }
                }
              }
            };
          });
    
    
          try {
            const result = babel.transform(source, options);
            console.log(JSON.stringify(result));
          } catch(e) {
            console.log(JSON.stringify({'error': e.name + ": " + e.message}));
            process.exit(1);
          }
        JS
  
        if result['error']
          raise Error, result['error']
        else
          input[:source] = result['code']
          input[:map] = result['map']
        end
      end
    end
    
  end
end