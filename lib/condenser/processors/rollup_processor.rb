require 'json'
require 'tmpdir'
require File.expand_path('../node_processor', __FILE__)

class Condenser
  class RollupProcessor < NodeProcessor

    ROLLUP_VERSION = '0.56.1'
    ROLLUP_SOURCE = File.expand_path('../rollup', __FILE__)
    
    def self.call(environment, input)
      new.call(environment, input)
    end
    
    def initialize(options = {})
      @options = options.merge({}).freeze
      
      # @cache_key = [
      #   self.class.name,
      #   Condenser::VERSION,
      #   SOURCE_VERSION,
      #   @options
      # ].freeze
    end

    def call(environment, input)
      @environment = environment
      @input = input
      
      Dir.mktmpdir do |output_dir|
        @entry = File.join(output_dir, 'entry.js')
        input_options = {
          input: @entry,
        }
        output_options = {
          file: File.join(output_dir, 'result.js'),
          format: 'iife',
          sourcemap: true
        }
        
        exec_runtime(<<-JS)
          const fs    = require('fs');
          const path  = require('path');
          const stdin = process.stdin;


          var buffer = '';
          stdin.resume();
          stdin.setEncoding('utf8');
          stdin.on('data', function (chunk) {
            buffer += chunk;
            try {
              var message = JSON.parse(buffer);
              stdin.emit('message', message);
              buffer = '';
            } catch(e) {
              if (e.name !== "SyntaxError") {
              console.log(JSON.stringify({method: 'error', args: [e.name, e.message]}));
                process.exit(1);
              }
            }
          });

          const rollup = require("#{ROLLUP_SOURCE}");

          function request(method, args) {
            var promise = new Promise(function(resolve, reject) {
              stdin.once('message', function(message) {
                resolve(message['return']);
              });
            });
  
            console.log(JSON.stringify({ method: method, args: args }));

            return promise;
          }

          const inputOptions = #{JSON.generate(input_options)};
          inputOptions.plugins = [];
          inputOptions.plugins.push({
            name: 'erb',
            resolveId: function (importee, importer) {
              return request('resolve', [importee, importer]).then(function(value) {
                return value;
              });
            },
            load: function(id) {
              return request('load', [id]).then(function(value) {
                return value;
              });
            }
          });
          const outputOptions = #{JSON.generate(output_options)};

          async function build() {
            try {
              const bundle = await rollup.rollup(inputOptions);
              await bundle.write(outputOptions);
              process.exit(0);
            } catch(e) {
              console.log(JSON.stringify({method: 'error', args: [e.name, e.message]}));
              process.exit(1);
            }
          }

          build();
        JS
        
        input[:source] = File.read(File.join(output_dir, 'result.js'))
        input[:source].delete_suffix!('//# sourceMappingURL=result.js.map')
        # asset.map = File.read(File.join(output_dir, 'result.js.map'))
      end
    end
    
    def exec_runtime(script)
      io = IO.popen([binary, '-e', script], 'r+')
      output = ''
      
      begin
        while line = io.readline
          output << line
          if message = JSON.parse(output)
            case message['method']
            when 'resolve'
              importee, importer = message['args']

              asset = if importer.nil? && importee == @entry
                @entry
              else
                @environment.find!(importee, importer ? File.dirname(importer) : nil)
              end
              
              io.write(JSON.generate({return: asset}))
            when 'load'
              if message['args'].first == @entry
                io.write(JSON.generate({return: {
                  code: @input[:source], map: @input[:map]
                }}))
              else
                asset = @environment.find!(message['args'].first)
                io.write(JSON.generate({return: {
                  code: asset.source, map: asset.sourcemap
                }}))
              end
            when 'error'
              raise exec_runtime_error(message['args'][0] + ': ' + message['args'][1])
            end
            output = ''
          end
        end
      rescue EOFError
      end
      
      io.close
      
      if $?.success?
        output
      else
        raise exec_runtime_error(output)
      end
    end
    
  end
end