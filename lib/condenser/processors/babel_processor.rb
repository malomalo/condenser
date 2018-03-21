require 'json'
require File.expand_path('../node_processor', __FILE__)

class Condenser
  class BabelProcessor < NodeProcessor
    class Error           < StandardError; end
    
    # From https://github.com/babel/babel-standalone/releases/download/release-6.26.0/babel.min.js
    BABEL_VERSION = '6.26.0'
    BABEL_SOURCE = File.expand_path('../babel.min.js', __FILE__)
    
    def self.call(input)
      new.call(input)
    end
    
    def initialize(options = {})
      @options = options.merge({
        ast: false,
        compact: false,
        presets: [ ["latest", { "es2015": { "modules": false } }] ],
        sourceMap: true
      }).freeze

      # @cache_key = [
      #   self.class.name,
      #   Condenser::VERSION,
      #   BABEL_VERSION,
      #   @options
      # ].freeze
    end

    def call(asset)
      # result = input[:cache].fetch(@cache_key + [data]) do
      
      opts = {
        # 'moduleRoot' => nil,
        'filename' => asset.filename,
        'moduleId' => asset.filename.sub(/(\..+)+/, ''),
        'filenameRelative' => asset.filename,#split_subpath(input[:load_path], input[:filename]),
        'sourceFileName' => asset.filename,
        'sourceMapTarget' => asset.filename
        # 'inputSourceMap'
      }.merge(@options)

      result = exec_runtime(<<-JS)
        const babel = require('#{BABEL_SOURCE}');
        const source = #{JSON.generate(asset.source)};
        const options = #{JSON.generate(opts)};

        try {
          const result = babel.transform(source, options);
          console.log(JSON.stringify(result));
        } catch(e) {
          console.log(JSON.stringify({'error': e.name + ": " + e.message}));
          process.exit(1);
        }
      JS

      if result['error']
        raise Error, result['error']
      else
        asset.source = result['code']
          # result['metadata']["modules"]["imports"].each do |import|
          #   asset.prepend(asset.environment.find!(import['source'], accept: asset.content_type))
          # end
          # asset.exports = !result['metadata']["modules"]["exports"]['exported'].empty?
        asset.sourcemap = result['map']
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