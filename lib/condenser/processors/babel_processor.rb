require 'json'

class Condenser::BabelProcessor < Condenser::NodeProcessor
  
  attr_accessor :options
  
  def initialize(dir = nil, options = {})
    super(dir)
    
    options[:plugins] ||= [
      ["@babel/plugin-transform-runtime", { corejs: 3, useESModules: true }]
    ]
    options[:presets] ||= [
      ['@babel/preset-env', {
        modules: false,
        targets: { browsers: '> 1% and not dead' }
      }]
    ]

    packages = options.slice(:plugins, :presets).values.reduce(&:+).map { |p| p.is_a?(Array) ? p[0] : p}
    packages.unshift('@babel/core')
    if packages.include?('@babel/plugin-transform-runtime')
      runtime = options[:plugins].find { |i| i.is_a?(Array) ? i[0] == '@babel/plugin-transform-runtime' : i == '@babel/plugin-transform-runtime' }
      packages << if runtime.is_a?(Array) && runtime[1][:corejs]
        if runtime[1][:corejs].is_a?(Hash)
          "@babel/runtime-corejs#{runtime[1][:corejs][:version]}"
        else
          "@babel/runtime-corejs#{runtime[1][:corejs]}"
        end
      else
        '@babel/runtime'
      end
    end
    
    npm_install(*packages)
    
    options[:plugins].map! do |plugin|
      if plugin.is_a?(Array)
        plugin[0] = npm_module_path(plugin[0])
        plugin
      else
        npm_module_path(plugin)
      end
    end
    
    options[:presets].map! do |plugin|
      if plugin.is_a?(Array)
        plugin[0] = npm_module_path(plugin[0])
        plugin
      else
        npm_module_path(plugin)
      end
    end

    @options = {
      ast:        false,
      compact:    false,
      sourceMap:  false
    }.merge(options)
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
    }.merge(@options).select { |k,v| !v.nil? }
    
    result = exec_runtime(<<-JS)
      const babel = require("#{File.join(npm_module_path('@babel/core'))}");
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
      if result['error'][0] == 'SyntaxError'
        raise exec_syntax_error(result['error'][1], "/assets/#{input[:filename]}")
      else
        raise exec_runtime_error(result['error'][0] + ': ' + result['error'][1])
      end
    else
      input[:source] = result['code']
      input[:map] = result['map']
      input[:export_dependencies] = result['imports'].map do |i|
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