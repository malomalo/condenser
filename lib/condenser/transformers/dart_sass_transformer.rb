class Condenser::DartSassTransformer < Condenser::NodeProcessor

  include Condenser::Sass::Functions
  
  ACCEPT = ['text/css', 'text/scss', 'text/sass']
  
  def self.syntax
    :sass
  end
  
  def initialize(dir, options = {})
    super(dir)
    npm_install('sass')
    
    @options = options.merge({
      indentedSyntax: self.class.syntax == :sass
    }).freeze
  end

  def call(environment, input)
    @context = environment.new_context_class#.new(environment)
    
    options = {
      verbose: true,
      file: File.join('/', input[:filename])
    }.merge(@options)
    @environment = environment
    @input = input

    result = exec_runtime(<<-JS)
      const fs    = require('fs');
      const sass = require("#{npm_module_path('sass')}");
      const stdin = process.stdin;
      stdin.resume();
      stdin.setEncoding('utf8');

      const source = #{JSON.generate(input[:source])};
      const options = #{JSON.generate(options)};

      var rid = 0;
      function request(method, ...args) {
        var trid = rid;
        rid += 1;
        console.log(JSON.stringify({ rid: trid, method: method, args: args }) + "\\n");

        var readBuffer = '';
        var response = undefined;
        let chunk = new Buffer(1024);
        let bytesRead;
        
        while (response === undefined) {
          try {
            bytesRead = fs.readSync(stdin.fd, chunk, 0, 1024);
            readBuffer += chunk.toString('utf8', 0, bytesRead);
            [readBuffer, response] = readResponse(readBuffer);
          } catch (e) {
             if (e.code !== 'EAGAIN') { throw e; }
          }
        }
        return response['return'];
      }
      
      function readResponse(buffer) {
        try {
          var message = JSON.parse(buffer);
          return ['', message];
        } catch(e) {
          if (e.name === "SyntaxError") {
            if (e.message.startsWith('Unexpected non-whitespace character after JSON at position ')) {
              let pos = parseInt(e.message.slice(59));
              let [b, r] = readResponse(buffer.slice(0,pos));
              console.error('1')
              return [b + buffer.slice(pos), r];
            } else if (e.message.startsWith('Unexpected token { in JSON at position ')) {
              // This can be removed, once dropping support for node <= v18
              var pos = parseInt(e.message.slice(39));
              let [b, r] = readResponse(buffer.slice(0,pos));
              console.error('2')
              return [b + buffer.slice(pos), r];
            } else {
              return [buffer, null];
            }
          } else {
            console.log(JSON.stringify({method: 'error', args: [e.name, e.message]}) + "\\n");
            process.exit(1);
          }
        }
      }
      
      
      options.importer = function(url, prev) { return request('load', url, prev); };
      
      const call_fn = function(name, url) {
        if (!(url instanceof sass.types.String)) { throw "$url: Expected a string."; }
        return new sass.types.String(request('call', name, url.getValue()));
      }
      options.functions = {};
      [
        "asset-path($url)", 
        "asset-url($url)", 
        "image-path($url)", 
        "image-url($url)", 
        "video-path($url)", 
        "video-url($url)", 
        "audio-path($url)", 
        "audio-url($url)", 
        "font-path($url)", 
        "font-url($url)", 
        "javascript-path($url)", 
        "javascript-url($url)", 
        "stylesheet-path($url)", 
        "stylesheet-url($url)", 
        "asset_data-url($url)"
      ].forEach( (f) => {
          let name = f.replace(/-/g, '_').replace(/\\(\\$url\\)/, '');
          options.functions[f] = (a) => call_fn(name, a);
        }
      )
      
      try {
        options.data = source;
        const result = sass.renderSync(options);
        request('result', result.css.toString());
        process.exit(0);
      } catch(e) {
        request('error', e.name, e.message);
        process.exit(1);
      }
    JS
    
    input[:source] = result
    # input[:map] = map.to_json({})
    input[:linked_assets]         += @context.links
    input[:process_dependencies]  += @context.dependencies
  end
  
  def find(importee, importer = nil)
    # importer ||= @input[:source_file]
    @environment.find(expand_path(importee, importer), nil, accept: ACCEPT)
  end
  
  def resolve(importee, importer = nil)
    # importer ||= @input[:source_file]
    @environment.resolve(expand_path(importee, importer), accept: ACCEPT)
  end
  
  def expand_path(path, base=nil)
    if path.start_with?('.')
      File.expand_path(path, File.dirname(base)).delete_prefix(File.expand_path('.') + '/')
    else
      File.expand_path(path).delete_prefix(File.expand_path('.') + '/')
    end
  end
  
  def exec_runtime(script)
    io = IO.popen([binary, '-e', script], 'r+')
    buffer = ''
    result = nil
    
    begin
      while IO.select([io]) && io_read = io.read_nonblock(1_024)
        buffer << io_read
        messages = buffer.split("\n\n")
        buffer = buffer.end_with?("\n\n") ? '' : messages.pop
        
        messages.each do |message|
          message = JSON.parse(message)
          ret = case message['method']
          when 'result'
            result = message['args'][0]
          when 'load'
            importee = message['args'][0]
            importer = message['args'][1]
            
            if importee.end_with?('*')
              @context.depend_on(importee)
              code = ""
              resolve(importee, importer).each do |f, i|
                code << "@import '#{f.source_file}';\n"
              end
              { contents: code, map: nil }
            else
              if asset = find(importee)
                @context.depend_on(asset.filename)
                { contents: asset.source, map: asset.sourcemap }
              else
                @context.depend_on(importee)
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
          when 'call'
            if respond_to?(message['args'][0])
              send(message['args'][0], message['args'][1])
            end
          end

          io.write(JSON.generate({rid: message['rid'], return: ret}))
        end
      end
    rescue Errno::EPIPE, EOFError
    end
    
    io.close
    if $?.success?
      result
    else
      raise exec_runtime_error(buffer)
    end
  end
  
  protected

  def condenser_context
    @context
  end
  
  def condenser_environment
    @environment
  end

  
end

class Condenser::DartScssTransformer < Condenser::DartSassTransformer
  def self.syntax
    :scss
  end
end
