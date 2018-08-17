require 'json'
require File.expand_path('../node_processor', __FILE__)

class Condenser
  class BabelProcessor < NodeProcessor
    class Error           < StandardError; end
    
    BABEL_VERSION = '7.0.0-rc.1'
    
    def self.call(environment, input)
      new.call(environment, input)
    end
    
    def initialize(options = {})
      @options = options.merge({
        ast: false,
        compact: false,
        plugins: [
          ["@babel/plugin-proposal-class-properties", {}],
          ['@babel/plugin-transform-runtime', {
                corejs: 2,
          }],
        ],
        presets: [["@babel/preset-env", {
          "modules": false,
          "targets": { "browsers": "> 1%" }
        } ]],
        sourceMap: true
      }).freeze

      # @cache_key = [
      #   self.class.name,
      #   Condenser::VERSION,
      #   BABEL_VERSION,
      #   @options
      # ].freeze
    end

    def call(environment, input)
      opts = {
        # 'moduleRoot' => nil,
        'filename' => input[:filename],
        'moduleId' => input[:filename].sub(/(\..+)+/, ''),
        'cwd' => '/assets/',
        'filenameRelative' => input[:filename],#split_subpath(input[:load_path], input[:filename]),
        'sourceFileName' => input[:filename],
        # 'sourceMapTarget' => input[:filename]
        # 'inputSourceMap'
      }.merge(@options)
      
      result = exec_runtime(<<-JS)
        module.paths.push("#{File.expand_path('../node_modules', __FILE__)}")
      
        const babel = require('@babel/core');
        const source = #{JSON.generate(input[:source])};
        const options = #{JSON.generate(opts).gsub(/"@babel\/[^"]+"/) { |m| "require(#{m})"}};
        
        let imports = [];
        options['plugins'].push(function({ types: t }) {
          return {
            visitor: {
              ImportDeclaration(path, state) {
                imports.push(path.node.source.value);
              }
            }
          };
        });
        
        
        try {
          const result = babel.transform(source, options);
          result.imports = imports;
          console.log(JSON.stringify(result));
        } catch(e) {
          console.log(JSON.stringify({'error': e.name + ": " + e.message}));
          process.exit(1);
        }
      JS
      
      if result['error']
        raise Error, result['error']
      else
        input[:source] = result['code']
        input[:map] = result['map']
        input[:dependencies] = result['imports'].map do |i|
          i.end_with?('.js') ? i : "#{i}.js"
        end
      end
    end
    
    # Internal: Get relative path for root path and subpath.
    #
    # path    - String path
    # subpath - String subpath of path
    #
    # Returns relative String path if subpath is a subpath of path, or nil if
    # subpath is outside of path.
    def split_subpath(path, subpath)
      return "" if path == subpath
      path = File.join(path, ''.freeze)
      if subpath.start_with?(path)
        subpath[path.length..-1]
      else
        nil
      end
    end
    
  end
end