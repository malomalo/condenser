# frozen_string_literal: true

require 'json'

class Condenser::BabelProcessor < Condenser::NodeProcessor
  
  attr_accessor :options

  # The versions installed when a package is missing, so a new major (e.g.
  # Babel 8, which removed options) doesn't break a fresh install. The other
  # @babel/ packages are installed at the major of the @babel/core installed.
  BABEL_MAJOR = 8
  NPM_VERSIONS = {
    'babel-plugin-polyfill-corejs3' => '^1',
    'core-js-pure'                  => '^3'
  }

  def initialize(dir = nil, **options)
    super(dir)
    
    # Babel 8 removed transform-runtime's corejs option; core-js polyfills
    # come from babel-plugin-polyfill-corejs3, imported from core-js-pure.
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
    packages.unshift('@babel/core')
    if packages.include?('@babel/plugin-transform-runtime')
      runtime = options[:plugins].find { |i| i.is_a?(Array) ? i[0] == '@babel/plugin-transform-runtime' : i == '@babel/plugin-transform-runtime' }
      packages << if runtime.is_a?(Array) && runtime[1][:corejs]
        if runtime[1][:corejs].is_a?(Hash)
          "@babel/runtime-corejs#{runtime[1][:corejs][:version]}"
        else
          "@babel/runtime-corejs#{runtime[1][:corejs]}"
        end
      elsif packages.include?('babel-plugin-polyfill-corejs3')
        # It has transform-runtime import helpers from @babel/runtime-corejs3.
        '@babel/runtime-corejs3'
      else
        '@babel/runtime'
      end
    end
    packages << 'core-js-pure' if packages.include?('babel-plugin-polyfill-corejs3')
    
    npm_install("@babel/core@^#{BABEL_MAJOR}")
    major = JSON.parse(File.read(npm_module_path('@babel/core/package.json')))['version'].to_i
    self.class.check_node_version(self)
    npm_install(*packages.map { |p|
      version = p.start_with?('@babel/') ? "^#{major}" : NPM_VERSIONS[p]
      version ? "#{p}@#{version}" : p
    })

    # Polyfill what the installed core-js-pure has (the default is core-js
    # 3.0's) for preset-env's targets (the default is Babel's).
    if default_plugins
      polyfill = options[:plugins][1][1]
      polyfill[:version] = JSON.parse(File.read(npm_module_path('core-js-pure/package.json')))['version']
      env = options[:presets].find { |p| p.is_a?(Array) && p[0] == '@babel/preset-env' }
      polyfill[:targets] = env[1][:targets] if env&.dig(1, :targets)
    end
    
    @options = {
      ast:        false,
      compact:    false,
      sourceMap:  false
    }.merge(options)
  end
  
  def self.check_node_version(node)
    return if JSON.parse(File.read(node.npm_module_path('@babel/core/package.json')))['version'].to_i < 8
    version = Gem::Version.new(node_version(node))
    if !(Gem::Requirement.new('~> 22.18').satisfied_by?(version) || version >= Gem::Version.new('24.11'))
      raise Condenser::Error, "Babel 8 needs Node ^22.18.0 || >=24.11.0, but #{node.binary} is #{version}"
    end
  end

  def self.node_version(node)
    @node_version ||= Open3.capture2(node.binary, '--version')[0].strip.delete_prefix('v')
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