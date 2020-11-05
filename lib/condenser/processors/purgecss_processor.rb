require 'json'

class Condenser::PurgeCSSProcessor < Condenser::NodeProcessor
  
  attr_accessor :options
  
  # Public: initialize with custom options.
  #
  # dir - String (path to node_modules directory)
  # options - Hash
  #   content - Array - html files to process
  #       ex. [File.expand_path('./docs-src/**/*.erb'), File.expand_path('./docs-src/assets/javascripts/**/*.js')]
  #
  # Options are passed to PurgeCSS checkout [PurgeCSS Configurations](https://purgecss.com/configuration.html)
  #
  
  def self.call(environment, input)
    @instances ||= {}
    @instances[environment] ||= new(environment.npm_path, {
      content: [File.join(environment.base, '**/*.html'), File.join(environment.base, '**/*.js')]
    })
    @instances[environment].call(environment, input)
  end
  
  
  def initialize(dir = nil, options = {})
    super(dir)
    @options = options
    npm_install('purgecss')
  end
  
  def call(environment, input)
    result = exec_runtime(<<-JS)
      const { PurgeCSS } = require("#{File.join(npm_module_path('purgecss'))}")
      const options = #{@options.to_json}
      options.css = [{
        raw: #{input[:source].inspect}
      }]
      if(options.safelist) {
        options.safelist = options.safelist.map(s => {
          if(s[0] == "/" && s[s.length - 1] == "/") {
            return new RegExp(s.slice(1, -1))
          }
          return s
        })
      }
      const result = new PurgeCSS().purge(options)
      try {
        result.then(
          r => console.log(JSON.stringify({
            success: r[0]
          })),
          function() {console.log(JSON.stringify({'error': arguments}))}
        )
      } catch(e) {
        console.log(JSON.stringify({'error': [e.name, e.message, e.stack]}));
      }
    JS
    if result['error']
      if result['error'][0] == 'SyntaxError'
        raise exec_syntax_error(result['error'][1], "/assets/#{input[:filename]}")
      else
        raise exec_runtime_error(result['error'][0] + ': ' + result['error'][1])
      end
    else
      input[:source] = result["success"]["css"]
    end
  end

end