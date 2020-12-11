class Condenser::TerserMinifier < Condenser::NodeProcessor

  def initialize(dir, options = {})
    super(dir)
    npm_install('terser')
    
    @options = options.merge({
      keep_classnames: true,
      keep_fnames: true
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


      Terser.minify(source, options).then((result) => {
        console.log(JSON.stringify(result));
      }, (error) => {
        console.log(JSON.stringify({'error': error.name + ": " + error.message}));
        process.exit(1);
      });
    JS

    exec_runtime_error(result['error']) if result['error']
    
    result['warnings']&.each { |w| environment.logger.warn(w) }
    
    input[:source] = result['code']
    input[:map] = result['map']
  end

end