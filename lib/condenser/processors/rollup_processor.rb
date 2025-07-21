# frozen_string_literal: true

require 'json'
require 'tmpdir'

class Condenser::RollupProcessor
  
  @@setup = []
  
  def self.setup(environment)
    install_npm_packages(environment.npm_path)
  end
  
  def self.install_npm_packages(npm_path)
    return if @@setup.include?(npm_path)
    
    ::Condenser::NodeProcessor.new(npm_path).npm_install(
      'rollup',
      '@rollup/plugin-commonjs',
      '@rollup/plugin-node-resolve',
      '@rollup/plugin-replace'
    )
    @@setup << npm_path
  end
  
  def self.call(environment, input)
    new(environment.npm_path).call(environment, input)
  end

  def name
    self.class.name
  end
  
  def options
    {prefix: @prefix, dynamic_imports: @dynamic_imports}
  end
  
  # @param prefix  [string] string to prefix to the url of dynamic imports
  # @param imports [symbol] :inline will inline all the imports in the 
  #                        output file if possible.
  #                        false will keep all the imports as imports.
  #                        :local will not inline URLS.
  # @param dynamic_imports [symbol] Default is :local
  #    :inline - Inline dynamic imports into the output file if possible.
  #    :local  - Same as :inline except for URLs are kept as URLs
  #    :keep   - Keep the dynamic imports but rewrite the import as a URL
  def initialize(dir = nil, prefix: nil, dynamic_imports: :inline)
    self.class.install_npm_packages(dir)
    @npm_dir = dir
    @prefix = prefix
    @dynamic_imports = dynamic_imports
  end

  def call(environment, input)
    Runner.new(@npm_dir, prefix: @prefix, dynamic_imports: @dynamic_imports).call(environment, input)
  end
  
  
  class Runner < Condenser::NodeProcessor
    def initialize(dir = nil, prefix: nil, dynamic_imports: :inline)
      super(dir)
      @prefix = prefix
      @dynamic_imports = dynamic_imports
    end

    def call(environment, input)
      @environment = environment
      @input = input
    
      @input_dir = File.realdirpath(Dir.mktmpdir)
      @output_dir = File.realdirpath(Dir.mktmpdir)
    
      @entry = File.join(@input_dir, 'entry.js')
    
      input_options = {
        input: @entry
      }
    
      output_options = {
        dir: @output_dir,
        format: 'es',
        globals: [],
        sourcemap: false,
        inlineDynamicImports: true,
        generatedCode: {
          arrowFunctions: true,
          constBindings: true,
          objectShorthand: true,
          preset: 'es2015',
        }
      }

      if input[:source] =~ /export\s+{[^}]+};?\z/i
        output_options[:name] = File.basename(input[:filename], ".*").capitalize
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
        const asyncWalk = require("#{npm_module_path('estree-walker')}").asyncWalk;
        const MagicString = require("#{npm_module_path('magic-string')}");
        const replace = require("#{npm_module_path('@rollup/plugin-replace')}");
      
        var rid = 0;
        var renderStack = {};
        var dynamicImports = {};
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
        
        inputOptions.plugins.push(replace({
            preventAssignment: true,
            values: {
              "process.env.NODE_ENV": JSON.stringify("production")
            }
        }), {
          name: 'transform',
          transform: async function(code, id) {
            const magicString = new MagicString(code);
            const ast = this.parse(code, { sourceType: 'module' });

            await asyncWalk(ast, {
              async enter(node) {
                if(['ImportExpression'].includes(node.type) && node.source.type == 'Literal') {
                  const asset = await request('resolveDynamicImport', [node.source.value, id]);

                  if (asset.export) {
                    dynamicImports[asset.source] = asset;
                    magicString.update(node.source.start, node.source.end, `'${asset.source}'`);
                  } else {
                    dynamicImports[node.source.value] = asset;
                  }
                } else if (node.type == 'ImportDeclaration' ) {
                  if (node.value == '@arcgis/lumina/controllers') {
                    magicString.update(node.start, node.end, `'@arcgis/components-controllers'`);
                  }
                }
              }
            });

            return {
              code: magicString.toString(),
              map: null
            };
          }
        }, {
          name: 'condenser',
          resolveDynamicImport: function (importee, importer, options) {
            const asset = dynamicImports[importee];
            request('resolve!!!!', [importee, dynamicImports]);

            if (!asset) {
              return;
            }
          
            if (asset.export) {
              return false;
            }
          
            return asset.source;
          },
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

            return request('load', [id]);
          }
        });
      
        inputOptions.plugins.push(nodeResolver);
        inputOptions.plugins.push(commonjs());
      
        const outputOptions = #{JSON.generate(output_options)};
        outputOptions.paths = (id) => {
            const asset = dynamicImports[id];
          
            if (asset) {
              return asset.path;
            }
        }

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

      input[:source] = File.read(File.join(@output_dir, 'entry.js'))
      input[:source].delete_suffix!("//# sourceMappingURL=result.js.map\n")
      input[:type] = 'module'
      # asset.map = File.read(File.join(output_dir, 'result.js.map'))
      input
    ensure
      begin
        [@input_dir, @output_dir].each { |dir| FileUtils.remove_entry(dir) }
      rescue Errno::ENOENT
      end
    end
  
    def exec_runtime(script, input)
      io = IO.popen([binary, '--max_old_space_size=5120', '-e', script], 'r+')
      buffer = String.new
    
      begin
      
        while IO.select([io]) && io_read = io.read_nonblock(1_024)
          buffer << io_read
          messages = buffer.split("\n\n")
        
          buffer = if buffer.end_with?("\n\n")
            String.new
          else
            messages.pop
          end
        
          messages.each do |message|
            message = JSON.parse(message)
            # puts message.inspect
            ret = case message['method']
            when 'log'
              puts message.inspect
            when 'resolveDynamicImport'
              importee, importer = message['args']

              asset = @environment.find(importee, importer ? (@entry == importer ? @input[:source_file] : importer) : nil, accept: @input[:content_types].last, npm: true)
              asset ||= @environment.find(importee.delete_suffix('.js') + "/index.js", importer ? (@entry == importer ? @input[:source_file] : importer) : nil, accept: @input[:content_types].last, npm: true)
              asset ||= @environment.find(importee.gsub(/\/[^\/]+$/, '')+ "/dist/index.js", importer ? (@entry == importer ? @input[:source_file] : importer) : nil, accept: @input[:content_types].last, npm: true)
            
              if asset.source_file == @input[:source_file]
                {
                  path: File.join("/", *[@prefix, asset.path].compact),
                  # source: File.join(@input_dir, asset.filename),
                  source: @entry,
                  export: false,
                  # filename: asset.filename
                }
              else
                if @dynamic_imports != :inline
                  {
                    path: File.join("/", *[@prefix, asset.path].compact),
                    source: File.join(@input_dir, asset.filename),
                    export: true,
                    filename: asset.filename
                  }
                else
                  {
                    export: false,
                    source: asset.source_file,
                    filename: asset.filename
                  }
                end
              end
            
            when 'resolve'
              importee, importer = message['args']

              if importer.nil? && importee == @entry
                @entry
              elsif importee.start_with?('@babel/runtime') || importee.start_with?('core-js-pure') || importee.start_with?('regenerator-runtime')
                x = File.join(npm_module_path, importee.gsub(/^\.\//, File.dirname(importer) + '/')).sub('/node_modules/regenerator-runtime', '/node_modules/regenerator-runtime/runtime.js')
                x = "#{x}.js" if !x.end_with?('.js', '.mjs')
                File.file?(x) ? x : (x.delete_suffix('.js') + "/index.js")
              elsif npm_module_path && importee&.start_with?(npm_module_path)
                x = importee.end_with?('.js', '.mjs') ? importee : "#{importee}.js"
                x = (x.delete_suffix('.js') + "/index.js") if !File.file?(x)
                x
              elsif importee.start_with?('.') && importer.start_with?(npm_module_path)
                x = File.expand_path(importee, File.dirname(importer))
                x = "#{x}.js" if !x.end_with?('.js', '.mjs')
                File.file?(x) ? x : (x.delete_suffix('.js') + "/index.js")
              elsif importee.end_with?('*')
                File.join(File.dirname(importee), '*')
              else
                asset = @environment.find(importee, importer ? (@entry == importer ? @input[:source_file] : importer) : nil, accept: @input[:content_types].last, npm: true)&.source_file
              end
            when 'load'
              importee = message['args'].first
              if importee == @entry
                { code: @input[:source], map: @input[:map] }
              elsif importee.end_with?('*')
                importees = @environment.resolve(importee, importer ? File.dirname(@entry == importer ? @input[:source_file] : importer) : nil, accept: @input[:content_types].last, npm: true)
                code = String.new
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
            # puts JSON.generate({rid: message['rid'], return: ret})
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
end