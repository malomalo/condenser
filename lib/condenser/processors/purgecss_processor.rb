require 'json'

class Condenser::PurgeCSSProcessor < Condenser::NodeProcessor
  
  attr_accessor :options
  
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