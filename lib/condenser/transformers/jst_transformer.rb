# frozen_string_literal: true

class Condenser::JstTransformer < Condenser::NodeProcessor
  
  def initialize(dir = nil)
    super(dir)
    
    npm_install('@babel/core')
  end

  def call(environment, input)
    opts = {
      filename:         input[:filename],
      moduleId:         input[:filename].sub(/(\..+)+/, ''),
      cwd:              '/assets/',
      filenameRelative: input[:filename],
      sourceFileName:   input[:filename],
      ast:              false,
      compact:          false,
      plugins:          []
    }

    result = exec_runtime(<<-JS)
      const babel = require("#{npm_module_path('@babel/core')}");
      const source = #{JSON.generate(input[:source])};
      const options = #{JSON.generate(opts).gsub(/"@?babel[\/-][^"]+"/) { |m| "require(#{m})"}};

      let scope = [['document', 'window']];
      
      options['plugins'].unshift(function({ types: t }) {
        return {
          visitor: {
            Identifier(path, state) {
              if ( path.parent.type === 'MemberExpression' && path.parent.object !== path.node) {
                return;
              }
              
              if ( path.parent.type === 'ImportSpecifier' ||
                   path.parent.type === 'ImportDefaultSpecifier' ||
                   path.parent.type === 'FunctionDeclaration' ||
                   path.parent.type === 'FunctionExpression' ||
                   path.parent.type === 'ArrowFunctionExpression' ||
                   path.parent.type === 'SpreadElement' ||
                   path.parent.type === 'CatchClause' ) {
                return;
              }
              
              if ( path.parent.type === 'ObjectProperty' && path.parent.key === path.node ) {
                return;
              }

              if ( !(path.node.name in global) &&
                   !scope.find((s) => s.find(v => v === path.node.name))
              ) {
                path.replaceWith(
                  t.memberExpression(t.identifier("locals"), path.node)
                );
              }
            }
          }
        };
      });
      

      options['plugins'].unshift(function({ types: t }) {
          return {
            visitor: {
              "FunctionDeclaration|FunctionExpression|ArrowFunctionExpression": {
                enter(path, state) {
                  if (path.node.id) { scope[scope.length-1].push(path.node.id.name); }
                  scope.push(path.node.params.map((n) => n.type === 'RestElement' ? n.argument.name : n.name));
                }
              },
              CatchClause: {
                enter(path, state) {
                  scope.push([]);
                  if (path.node.param.name) { scope[scope.length-1].push(path.node.param.name); }
                }
              },
              Scopable: {
                enter(path, state) {
                  if (path.node.type !== 'Program' &&
                      path.node.type !== 'CatchClause' &&
                      path.parent.type !== 'FunctionDeclaration' &&
                      path.parent.type !== 'FunctionExpression' &&
                      path.parent.type !== 'ArrowFunctionExpression' &&
                      path.parent.type !== 'ExportDefaultDeclaration') {
                    scope.push([]);
                  }
                },
                exit(path, state) {
                  if (path.node.type !== 'Program' &&
                      path.parent.type !== 'ExportDefaultDeclaration') {
                    scope.pop();
                  }
                }
              },
              ImportDeclaration(path, state) {
                path.node.specifiers.forEach((s) => scope[scope.length-1].push(s.local.name));
              },
              ClassDeclaration(path, state) {
                if (path.node.id) {
                  scope[scope.length-1].push(path.node.id.name)
                }
              },
              VariableDeclaration(path, state) {
                path.node.declarations.forEach((s) => scope[scope.length-1].push(s.id.name));
              }
            }
          };
      });


      try {
        const result = babel.transform(source, options);
        console.log(JSON.stringify(result));
      } catch(e) {
        console.log(JSON.stringify({'error': [e.name, e.message, e.stack]}));
        process.exit(0);
      }
    JS

    if result['error']
      if result['error'][0] == 'SyntaxError'
        raise exec_syntax_error(result['error'][1], "/assets/#{input[:filename]}")
      else
        raise exec_runtime_error(result['error'][0] + ': ' + result['error'][1])
      end
    else
      input[:source] = result['code']
    end
    
    environment.preprocessors['application/javascript']&.each do |processor|
      processor_klass = (processor.is_a?(Class) ? processor : processor.class)
      input[:processors] << processor_klass.name
      environment.load_processors(processor_klass)
      processor.call(environment, input)
    end
  end

end