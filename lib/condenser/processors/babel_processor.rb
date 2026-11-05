# frozen_string_literal: true

require 'json'

class Condenser::BabelProcessor < Condenser::NodeProcessor
  
  attr_accessor :options

  BABEL_MAJOR = 8
  NPM_VERSIONS = {
    'babel-plugin-polyfill-corejs3' => '^1',
    'core-js-pure'                  => '^3'
  }

  def initialize(dir = nil, **options)
    super(dir)
    
    default_plugins = !options[:plugins]
    options[:plugins] ||= [
      "@babel/plugin-transform-runtime",
      ["babel-plugin-polyfill-corejs3", { method: 'usage-pure' }]
    ]
    options[:presets] ||= [
      ['@babel/preset-env', {
        modules: false,
        targets: { browsers: '> 1% and not dead' }
      }]
    ]
    options[:highlightCode] = false if !options.has_key?(:highlightCode)

    packages = options.slice(:plugins, :presets).values.reduce(&:+).map { |p| p.is_a?(Array) ? p[0] : p}
    if packages.include?('@babel/plugin-transform-runtime')
      runtime = options[:plugins].find { |i| i.is_a?(Array) ? i[0] == '@babel/plugin-transform-runtime' : i == '@babel/plugin-transform-runtime' }
      packages << if runtime.is_a?(Array) && runtime[1][:corejs]
        if runtime[1][:corejs].is_a?(Hash)
          "@babel/runtime-corejs#{runtime[1][:corejs][:version]}"
        else
          "@babel/runtime-corejs#{runtime[1][:corejs]}"
        end
      elsif packages.include?('babel-plugin-polyfill-corejs3')
        '@babel/runtime-corejs3'
      else
        '@babel/runtime'
      end
    end
    packages << 'core-js-pure' if packages.include?('babel-plugin-polyfill-corejs3')
    
    npm_install("@babel/core@^#{BABEL_MAJOR}")
    major = JSON.parse(File.read(npm_module_path('@babel/core/package.json')))['version'].to_i
    check_engines('@babel/core')
    npm_install(*packages.map { |p|
      version = p.start_with?('@babel/') ? "^#{major}" : NPM_VERSIONS[p]
      version ? "#{p}@#{version}" : p
    })
    mismatched = packages.grep(/\A@babel\//).map { |p| [p, JSON.parse(File.read(npm_module_path("#{p}/package.json")))['version']] }.reject { |_, v| v.to_i == major }
    if !mismatched.empty?
      raise Condenser::Error, "The @babel/ packages in #{npm_path} must have the major of @babel/core (#{major}): #{mismatched.map { |p, v| "#{p} is #{v}" }.join(', ')}"
    end

    if default_plugins
      polyfill = options[:plugins][1][1]
      polyfill[:version] = JSON.parse(File.read(npm_module_path('core-js-pure/package.json')))['version']
      env = options[:presets].find { |p| p.is_a?(Array) && p[0] == '@babel/preset-env' }
      targets = env&.dig(1, :targets) || env&.dig(1, 'targets')
      polyfill[:targets] = targets if targets
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
      'cwd' => '/assets/',
      'filenameRelative' => input[:filename],
      'sourceFileName' => input[:filename]
      # 'sourceMapTarget' => input[:filename]
      # 'inputSourceMap'
    }.merge(@options).select { |k,v| !v.nil? }
    
    if match = input[:source].match(/\A(\/\/[^\n]*(\n|\z))*/)
      directives = match.to_s.split(/\n/).map { |l| l.delete_prefix("//").strip }
      directives.each do |directive|
        if directive.start_with?('depends_on')
          input[:depends_on] << directive.sub(/\Adepends_on\s+/, '')
        end
      end
    end
    
    result = exec_runtime(<<-JS, logger: environment.logger)
      const babel = require("#{File.join(npm_module_path('@babel/core'))}");
      const source = #{JSON.generate(input[:source])};
      const options = #{JSON.generate(opts)};

      // Resolved from the npm path by node, since some packages (e.g.
      // babel-plugin-polyfill-corejs3) only have an "exports" entry point.
      const paths = [#{JSON.generate(npm_path)}];
      const resolve = (p) => Array.isArray(p) ? [require.resolve(p[0], { paths }), ...p.slice(1)] : require.resolve(p, { paths });
      options['plugins'] = options['plugins'].map(resolve);
      options['presets'] = options['presets'].map(resolve);
      
      let imports = [];
      let defaultExport = false;
      let hasExports = false;
      options['plugins'].push(function({ types: t }) {
        return {
          visitor: {
            ImportDeclaration(path, state) {
              imports.push(path.node.source.value);
            },

            ExportDeclaration(path, state) {
              hasExports = true;
              if (path.node.source) {
                imports.push(path.node.source.value);
              }
            },

            ExportDefaultDeclaration(path, state) {
              defaultExport = true;
            }
          }
        };
      });
      
      
      try {
        const result = babel.transformSync(source, options);
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
      input[:sourcemap] = result['map']
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