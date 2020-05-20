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

      function globalVar(scope, name) {
        if (name in scope.globals) {
          return true;
        } else if (scope.parent === null) {
          return false;
        } else {
          return globalVar(scope.parent, name);
        }
      }

      options['plugins'].unshift(function({ types: t }) {
        return {
          visitor: {
            Identifier(path, state) {
              if ( path.parent.type == 'MemberExpression' && path.parent.object != path.node) {
                return;
              }
              if ( path.parent.type == 'ImportSpecifier' || path.parent.type == 'ImportDefaultSpecifier' || path.parent.type =='FunctionDeclaration') {
                return;
              }

              if (
                path.node.name !== 'document' &&
                path.node.name !== 'window' &&
                !(path.node.name in global) &&
                globalVar(path.scope, path.node.name)
              ) {
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