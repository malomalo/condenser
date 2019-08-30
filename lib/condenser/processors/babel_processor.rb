require 'json'
require File.expand_path('../node_processor', __FILE__)

class Condenser::BabelProcessor < Condenser::NodeProcessor
  
  class Error < StandardError
  end
  
  # npm install @babel/core @babel/runtime-corejs3 @babel/plugin-transform-runtime @babel/preset-env rollup rollup-plugin-commonjs  rollup-plugin-node-resolve  @babel/plugin-proposal-class-properties babel-plugin-transform-class-extended-hook
  
  def self.call(environment, input)
    new.call(environment, input)
  end
  
  def initialize(options = {})
    @options = options.merge({
      ast: false,
      compact: false,
      plugins: [
        ['babel-plugin-transform-class-extended-hook', {}],
        ["@babel/plugin-proposal-class-properties", {}],
        ['@babel/plugin-transform-runtime', {
              corejs: 3,
        }],
      ],
      presets: [["@babel/preset-env", {
        "modules": false,
        "targets": { "browsers": "> 1% and not dead" }
      } ]],
      sourceMap: true
    }).freeze
  end

  def call(environment, input)
    opts = {
      # 'moduleRoot' => nil,
      'filename' => input[:filename],
      'moduleId' => input[:filename].sub(/(\..+)+/, ''),
      'cwd' => '/assets/',
      'filenameRelative' => input[:filename],
      'sourceFileName' => input[:filename]
      # 'sourceMapTarget' => input[:filename]
      # 'inputSourceMap'
    }.merge(@options)
    
    result = exec_runtime(<<-JS)
      module.paths.push("#{File.expand_path('../node_modules', __FILE__)}")
    
      const babel = require('@babel/core');
      const source = #{JSON.generate(input[:source])};
      const options = #{JSON.generate(opts).gsub(/"@?babel[\/-][^"]+"/) { |m| "require(#{m})"}};
      
      let imports = [];
      let defaultExport = false;
      let hasExports = false;
      options['plugins'].push(function({ types: t }) {
        return {
          visitor: {
            ImportDeclaration(path, state) {
              imports.push(path.node.source.value);
            },
            ExportDefaultDeclaration(path, state) {
              hasExports = true;
              defaultExport = true;
            },
            ExportDefaultSpecifier(path, state) {
              hasExports = true;
              defaultExport = true;
            },
            ExportAllDeclaration(path, state) {
              hasExports = true;
            },
            ExportNamedDeclaration(path, state) {
              hasExports = true;
            },
            ExportSpecifier(path, state) {
              hasExports = true;
            },
          }
        };
      });
      
      
      try {
        const result = babel.transform(source, options);
        result.imports = imports;
        result.exports = hasExports;
        result.defaultExport = defaultExport;
        console.log(JSON.stringify(result));
      } catch(e) {
        console.log(JSON.stringify({'error': [e.name, e.message, e.stack]}));
        process.exit(0);
      }
    JS
    
    if result['error']
      raise exec_runtime_error(result['error'][0] + ': ' + result['error'][1])
    else
      input[:source] = result['code']
      input[:map] = result['map']
      input[:dependencies] = result['imports'].map do |i|
        i.end_with?('.js') ? i : "#{i}.js"
      end
      input[:default_export] = result['defaultExport']
      input[:exports] = result['exports']
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