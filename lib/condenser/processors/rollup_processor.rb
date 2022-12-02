require 'json'
require 'tmpdir'

class Condenser::RollupProcessor < Condenser::NodeProcessor
  
  attr_accessor :options
  
  def initialize(dir = nil, options = {})
    super(dir)
    npm_install('rollup', '@rollup/plugin-commonjs', '@rollup/plugin-node-resolve')
    
    @options = options.freeze
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
        globals: [],
        sourcemap: true
      }
      if input[:source] =~ /export\s+{[^}]+};?\z/i
        output_options[:name] = File.basename(input[:filename], ".*").capitalize
        # output_options[:output][:name] = File.basename(input[:filename], ".*").capitalize
      end
      
      exec_runtime(<<-JS, @entry)
        const fs    = require('fs');
        const path  = require('path');
        const stdin = process.stdin;

        module.paths.push("#{File.join(npm_path, 'node_modules')}")

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
              if (e.message.startsWith('Unexpected non-whitespace character after JSON at position ')) {
                var pos = parseInt(e.message.slice(59));
                emitMessages(buffer.slice(0,pos));
                return emitMessages(buffer.slice(pos));
              } else if (e.message.startsWith('Unexpected token { in JSON at position ')) {
                // This can be removed, once dropping support for node <= v18
                var pos = parseInt(e.message.slice(39));
                emitMessages(buffer.slice(0,pos));
                return emitMessages(buffer.slice(pos));
              } else {
                return buffer;
              }
            } else {
              console.log(JSON.stringify({method: 'error', args: [e.name, e.message]}) + "\\n");
              process.exit(1);
            }
          }
        }

        stdin.on('data', function (chunk) {
          buffer += chunk;
          buffer = emitMessages(buffer);
        });
        
        const rollup = require("#{npm_module_path('rollup')}");
        const commonjs = require("#{npm_module_path('@rollup/plugin-commonjs')}");
        const nodeResolve = require("#{npm_module_path('@rollup/plugin-node-resolve')}").nodeResolve;
        var rid = 0;
        var renderStack = {};
        var nodeResolver = null;
        
        function request(method, args) {
          var trid = rid;
          rid += 1;
          var promise = new Promise(function(resolve, reject) {
            stdin.once('message' + trid, function(message) {
              resolve(message['return']);
            });
          });

          console.log(JSON.stringify({ rid: trid, method: method, args: args }) + "\\n");

          return promise;
        }

        if ('#{environment.npm_path}' !== '') {
          nodeResolver = nodeResolve({
            mainFields: ['module', 'main'],
            // modulesOnly: true,
            // preferBuiltins: false,
            moduleDirectories: [],
            modulePaths: ['#{npm_module_path}']
          });
        }

        const inputOptions = #{JSON.generate(input_options)};
        inputOptions.plugins = [];
        inputOptions.plugins.push({
          name: 'condenser',
          resolveId: function (importee, importer, options) {
            if (importee.startsWith('\\0') || (importer && importer.startsWith('\\0'))) {
              return null;
            }

            if (!(importer in renderStack)) {
              renderStack[importer] = [];
            }

            return request('resolve', [importee, importer]).then((value) => {
                if (!(value === null || value === undefined) && !renderStack[importer].includes(value)) {
                  renderStack[importer].push(value);
                }
                return value;
            });
          },
          load: function(id) {
            if (id.startsWith('\\0')) {
              return null;
            }

            return request('load', [id]).then(function(value) {
              return value;
            });
          }
        });
        
        inputOptions.plugins.push(nodeResolver);
        inputOptions.plugins.push(commonjs());
        
        inputOptions.plugins.push({
          name: 'nullHanlder',
          resolveId: function (importee, importer) {
            request('error', ["AssetNotFound", importee, importer, renderStack]).then(function(value) {
              process.exit(1);
            });
          }
        });

        const outputOptions = #{JSON.generate(output_options)};

        async function build() {
          try {
            // inputOptions.cache = await JSON.parse(request('get_cache', []));
            
            const bundle = await rollup.rollup(inputOptions);
            await bundle.write(outputOptions);
            // await request('set_cache', [JSON.stringify(bundle)]);
            process.exit(0);
          } catch(e) {
            await request('error', [e.name, e.message, e.stack]);
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
  
  def exec_runtime(script, input)
    io = IO.popen([binary, '-e', script], 'r+')
    buffer = ''
    
    begin
      
      while IO.select([io]) && io_read = io.read_nonblock(1_024)
        buffer << io_read
        messages = buffer.split("\n\n")
        
        buffer = if buffer.end_with?("\n\n")
          ''
        else
          messages.pop
        end
        
        messages.each do |message|
          message = JSON.parse(message)
          
          ret = case message['method']
          when 'resolve'
            importee, importer = message['args']

            if importer.nil? && importee == @entry
              @entry
            elsif importee.start_with?('@babel/runtime') || importee.start_with?('core-js-pure') || importee.start_with?('regenerator-runtime')
              x = File.join(npm_module_path, importee.gsub(/^\.\//, File.dirname(importer) + '/')).sub('/node_modules/regenerator-runtime', '/node_modules/regenerator-runtime/runtime.js')
              x = "#{x}.js" if !x.end_with?('.js')
              File.file?(x) ? x : (x.delete_suffix('.js') + "/index.js")
            elsif npm_module_path && importee&.start_with?(npm_module_path)
              x = importee.end_with?('.js') ? importee : "#{importee}.js"
              x = (x.delete_suffix('.js') + "/index.js") if !File.file?(x)
              x
            elsif importee.start_with?('.') && importer.start_with?(npm_module_path)
              x = File.expand_path(importee, File.dirname(importer))
              x = "#{x}.js" if !x.end_with?('.js')
              File.file?(x) ? x : (x.delete_suffix('.js') + "/index.js")
            elsif importee.end_with?('*')
              File.join(File.dirname(importee), '*')
            else
              @environment.find(importee, importer ? File.dirname(@entry == importer ? @input[:source_file] : importer) : nil, accept: @input[:content_types].last)&.source_file
            end
          when 'load'
            importee = message['args'].first
            if importee == @entry
              { code: @input[:source], map: @input[:map] }
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
              
              code += "export default [#{code_imports.join(', ')}];"

              { code: code, map: nil }
            else
              asset = @environment.find(importee, accept: @input[:content_types].last)
              if asset
                { code: asset.source, map: asset.sourcemap }
              else
                nil
              end
            end
          when 'error'
            io.write(JSON.generate({rid: message['rid'], return: nil}))
            
            case message['args'][0]
            when 'AssetNotFound'
              error_message = "Could not find import \"#{message['args'][1]}\" for \"#{message['args'][2]}\".\n\n"
              error_message << build_tree(message['args'][3], input, message['args'][2])
              raise exec_runtime_error(error_message)
            else
              raise exec_runtime_error(message['args'][0] + ': ' + message['args'][1])
            end
          # when 'set_cache'
          #   @environment.cache.set('rollup', message['args'][0])
          #   io.write(JSON.generate({rid: message['rid'], return: true}))
          # when 'get_cache'
          #   io.write(JSON.generate({rid: message['rid'], return: [(@environment.cache.get('rollup') || '{}')] }))
          end

          io.write(JSON.generate({rid: message['rid'], return: ret}))
        end
      end
    rescue Errno::EPIPE, EOFError
    end
    
    io.close
    if $?.success?
      true
    else
      raise exec_runtime_error(buffer)
    end
  end

  def build_tree(renderStack, from, to, visited: nil)
    visited ||= []
    return if visited.include?(from)
    visited << from
    
    if renderStack[from].nil? || renderStack[from].empty?
      nil
    elsif renderStack[from].include?(to)
      from
    else
      renderStack[from].each do |dep|
        if tree = build_tree(renderStack, dep, to, visited: visited)
          return "#{from}\n└ #{tree.lines.each_with_index.map{|l, i| "#{i == 0 ? '' : '    '}#{l}"}.join("")}"
        end
      end
      nil
    end
  end
  
end