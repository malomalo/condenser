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
          input: @entry
        }
        output_options = {
          file: File.join(output_dir, 'result.js'),
          format: 'iife',
          # output: { sourcemap: true, format: 'iife' },
          sourcemap: true
        }
        if input[:source] =~ /export\s+{[^}]+};?\z/i
          output_options[:name] = File.basename(input[:filename], ".*").capitalize
          # output_options[:output][:name] = File.basename(input[:filename], ".*").capitalize
        end

        exec_runtime(<<-JS)
          const fs    = require('fs');
          const path  = require('path');
          const stdin = process.stdin;

          module.paths.push("#{File.expand_path('../node_modules', __FILE__)}")

          var buffer = '';
          stdin.resume();
          stdin.setEncoding('utf8');
          function emitMessages(buffer) {
            try {
              var message = JSON.parse(buffer);
              stdin.emit('message' + message.rid, message);
              return '';
            } catch(e) {
              if (e.name === "SyntaxError") {
                if (e.message.startsWith('Unexpected token { in JSON at position ')) {
                  var pos = parseInt(e.message.slice(39));
                  emitMessages(buffer.slice(0,pos));
                  return emitMessages(buffer.slice(pos));
                } else {
                  return buffer;
                }
              } else {
                console.log(JSON.stringify({method: 'error', args: [e.name, e.message]}));
                process.exit(1);
              }
            }
          }

          stdin.on('data', function (chunk) {
            buffer += chunk;
            buffer = emitMessages(buffer);
          });
          
          const rollup = require("rollup");
          const commonjs = require('rollup-plugin-commonjs');
          const nodeResolve = require('rollup-plugin-node-resolve');
          var rid = 0;
          
          function request(method, args) {
            var trid = rid;
            rid += 1;
            var promise = new Promise(function(resolve, reject) {
              stdin.once('message' + trid, function(message) {
                resolve(message['return']);
              });
            });
  
            console.log(JSON.stringify({ rid: trid, method: method, args: args }));

            return promise;
          }

          const inputOptions = #{JSON.generate(input_options)};
          inputOptions.plugins = [];
          inputOptions.plugins.push({
            name: 'erb',
            resolveId: function (importee, importer) {
              if (importee.startsWith('\\0') || (importer && importer.startsWith('\\0'))) {
                return;
              }
              
              return request('resolve', [importee, importer]).then(function(value) {
                return value;
              });
            },
            load: function(id) {
              if (id.startsWith('\\0')) {
                return;
              }

              return request('load', [id]).then(function(value) {
                return value;
              });
            }
          });

          if ('#{environment.npm_path}' !== '') {
            inputOptions.plugins.push(nodeResolve({
              mainFields: ['module', 'main'],
              modulesOnly: true,
              customResolveOptions: {
                moduleDirectory: '#{environment.npm_path}'
              }
            }));
          }

          inputOptions.plugins.push(commonjs());

          const outputOptions = #{JSON.generate(output_options)};

          async function build() {
            try {
              // inputOptions.cache = await JSON.parse(request('get_cache', []));
              
              const bundle = await rollup.rollup(inputOptions);
              await bundle.write(outputOptions);
              // await request('set_cache', [JSON.stringify(bundle)]);
              process.exit(0);
            } catch(e) {
              console.log(JSON.stringify({method: 'error', args: [e.name, e.message, e.stack]}));
              process.exit(1);
            }
          }

          build();
        JS
        
        input[:source] = File.read(File.join(output_dir, 'result.js'))
        input[:source].delete_suffix!("//# sourceMappingURL=result.js.map\n")
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
            t = Time.now.to_f
            case message['method']
            when 'resolve'
              importee, importer = message['args']

              asset = if importer.nil? && importee == @entry
                @entry
              elsif importee.start_with?('@babel/runtime') || importee.start_with?('core-js/library') || importee.start_with?('regenerator-runtime')
                x = File.expand_path('../node_modules/' + importee.gsub(/^\.\//, File.dirname(importer) + '/'), __FILE__).sub('/node_modules/regenerator-runtime', '/node_modules/regenerator-runtime/runtime.js')
                x = "#{x}.js" if !x.end_with?('.js')
                if File.file?(x)
                  x
                else
                  x.delete_suffix('.js') + "/index.js"
                end
              elsif importer.start_with?(File.expand_path('../node_modules/', __FILE__))
                x = File.expand_path(importee, File.dirname(importer))
                x.end_with?('.js') ? x : "#{x}.js"
              elsif @environment.npm_path &&
                    importer.start_with?(@environment.npm_path) &&
                    File.file?(File.expand_path(importee, File.dirname(importer))) &&
                    File.file?(File.expand_path(importee, File.dirname(importer)) + '.js')
                x = File.expand_path(importee, File.dirname(importer))
                x.end_with?('.js') ? x : "#{x}.js"
              else
                x = @environment.find(importee, importer ? File.dirname(@entry == importer ? @input[:source_file] : importer) : nil, accept: @input[:content_types].last)&.source_file
                if importee.end_with?('*')
                  File.join(File.dirname(x), '*')
                else
                  x
                end
              end
              begin
                io.write(JSON.generate({rid: message['rid'], return: asset}))
              rescue Errno::EPIPE
                puts io.read
                raise
              end
            when 'load'
              importee = message['args'].first
              if importee == @entry
                io.write(JSON.generate({rid: message['rid'], return: {
                  code: @input[:source], map: @input[:map]
                }}))
              elsif importee.start_with?(File.expand_path('../node_modules/', __FILE__))
                io.write(JSON.generate({rid: message['rid'], return: {
                  code: File.read(importee), map: nil
                }}))
              elsif importee.end_with?('*')
                importees = @environment.resolve(importee, importer ? File.dirname(@entry == importer ? @input[:source_file] : importer) : nil, accept: @input[:content_types].last)
                code = ""
                code_imports = [];
                importees.each_with_index.map do |f, i|
                  if f.has_default_export?
                    code << "import _#{i} from '#{f.source_file}';\n"
                    code_imports << "_#{i}"
                  elsif f.has_exports?
                    code << "import * as _#{i} from '#{f.source_file}';\n"
                    code_imports << "_#{i}"
                  else
                    code << "import '#{f.source_file}';\n"
                  end
                end
                if !code_imports.empty?
                  code += "export default [#{code_imports.join(', ')}];"
                end

                io.write(JSON.generate({
                  rid: message['rid'],
                  return: {
                    code: code,
                    map: nil
                  }
                }))
                
              else
                asset = @environment.find(importee, accept: @input[:content_types].last)
                if asset
                  io.write(JSON.generate({rid: message['rid'], return: {
                    code: asset.source, map: asset.sourcemap
                  }}))
                else
                  io.write(JSON.generate({rid: message['rid'], return: nil}))
                end
              end
            when 'error'
              raise exec_runtime_error(message['args'][0] + ': ' + message['args'][1])
            # when 'set_cache'
            #   @environment.cache.set('rollup', message['args'][0])
            #   io.write(JSON.generate({rid: message['rid'], return: true}))
            # when 'get_cache'
            #   io.write(JSON.generate({rid: message['rid'], return: [(@environment.cache.get('rollup') || '{}')] }))
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