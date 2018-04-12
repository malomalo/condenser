# require File.expand_path('../../node_processor', __FILE__)

class Condenser
  class UglifyMinifier < NodeProcessor
    class Error           < StandardError; end
    
    # From npm install uglify-js
    UGLIFY_VERSION = '3.3.18'
    UGLIFY_SOURCE = File.expand_path('../node_modules', __FILE__)
    
    def self.call(environment, input)
      new.call(environment, input)
    end
    
    def initialize(options = {})
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
        module.paths.push("#{UGLIFY_SOURCE}")
        const UglifyJS = require("uglify-js");
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
          # result['metadata']["modules"]["imports"].each do |import|
          #   asset.prepend(asset.environment.find!(import['source'], accept: asset.content_type))
          # end
          # asset.exports = !result['metadata']["modules"]["exports"]['exported'].empty?
      input[:map] = result['map']
    end
    
  end
end