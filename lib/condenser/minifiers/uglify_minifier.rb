# From npm install uglify-js
class Condenser::UglifyMinifier < Condenser::NodeProcessor

  class Error < StandardError
  end
  
  def initialize(dir, options = {})
    super(dir)
    npm_install('uglify-js')
    
    @options = options.merge({
      warnings: true
    }).freeze
  end

  def call(environment, input)
    opts = {
      # 'moduleRoot' => nil,
      # 'filename' => input[:filename],
      # 'moduleId' => input[:filename].sub(/(\..+)+/, ''),
      # 'filenameRelative' => input[:filename],#split_subpath(input[:load_path], input[:filename]),
      # 'sourceFileName' => input[:filename],
      # 'sourceMapTarget' => input[:filename]
      # # 'inputSourceMap'
    }.merge(@options)
    
    result = exec_runtime(<<-JS)
      const UglifyJS = require("#{npm_module_path('uglify-js')}");
      const source = #{JSON.generate(input[:filename] => input[:source])}
      const options = #{JSON.generate(opts)};

      // {
      //     sourceMap: {
      //         content: "content from compiled.js.map",
      //         url: "minified.js.map"
      //     }
      // });
      
      try {
        var result = UglifyJS.minify(source, options);
        console.log(JSON.stringify(result));
      } catch(e) {
        console.log(JSON.stringify({'error': e.name + ": " + e.message}));
        process.exit(1);
      }
    JS

    raise Error, result['error'] if result['error']
    
    if result['warnings']
      result['warnings'].each { |w| environment.logger.warn(w) }
    end
    
    input[:source] = result['code']
    input[:map] = result['map']
  end

end