class Condenser::EjsTransformer < Condenser::NodeProcessor

  STRICT = true
  
  def self.setup(environment)
    require 'ejs' unless defined?(::EJS)

    if !environment.path.include?(EJS::ASSET_DIR)
      environment.append_path(EJS::ASSET_DIR)
    end
  end
  
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
        plugins: [
          ["#{File.expand_path('../../processors/node_modules', __FILE__)}/babel-plugin-transform-class-extended-hook", {}],
          ["#{File.expand_path('../../processors/node_modules', __FILE__)}/@babel/plugin-proposal-class-properties", {}],
          ["#{File.expand_path('../../processors/node_modules', __FILE__)}/@babel/plugin-transform-runtime", {
                corejs: 3,
          }],
        ],
        presets: [["#{File.expand_path('../../processors/node_modules', __FILE__)}/@babel/preset-env", {
          "modules": false,
          "targets": { "browsers": "> 1% and not dead" }
        } ]],
        sourceMap: true
      }

      result = exec_runtime(<<-JS)
        const babel = require("#{File.expand_path('../../processors/node_modules', __FILE__)}/@babel/core");
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