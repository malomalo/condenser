class Condenser::TerserMinifier < Condenser::NodeProcessor

  def initialize(dir, options = {})
    super(dir)
    npm_install('terser')
    
    @options = options.merge({
      warnings: true,
      sourceMap: false,
      keep_classnames: true
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
      const Terser = require("#{npm_module_path('terser')}");
      const source = #{JSON.generate(input[:filename] => input[:source])}
      const options = #{JSON.generate(opts)};


      var result = Terser.minify(source, options);
      if (result.error !== undefined) {
        console.log(JSON.stringify({'error': result.error.name + ": " + result.error.message}));
        process.exit(1);
      } else {
        console.log(JSON.stringify(result));
      }
    JS

    exec_runtime_error(result['error']) if result['error']
    
    result['warnings']&.each { |w| environment.logger.warn(w) }
    
    input[:source] = result['code']
    input[:map] = result['map']
  end

end