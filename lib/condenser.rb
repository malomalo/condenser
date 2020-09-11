require 'logger'
require 'active_support'
require 'active_support/core_ext'

require 'condenser/version'
require 'condenser/errors'
require 'condenser/environment'
require 'condenser/pipeline'
require 'condenser/resolve'
require 'condenser/encoding_utils'
require 'condenser/asset'
require 'condenser/manifest'

class Condenser
  
  prepend Environment, Pipeline, Resolve
  
  autoload :BabelProcessor,   'condenser/processors/babel_processor'
  autoload :RollupProcessor,  'condenser/processors/rollup_processor'
  autoload :JSAnalyzer,       'condenser/processors/js_analyzer'
  autoload :NodeProcessor,    'condenser/processors/node_processor'
  autoload :UglifyMinifier,   'condenser/minifiers/uglify_minifier'
  autoload :TerserMinifier,   'condenser/minifiers/terser_minifier'
  autoload :Erubi,            'condenser/templating_engine/erb'
  autoload :SassMinifier,     'condenser/minifiers/sass_minifier'
  autoload :SassTransformer,  'condenser/transformers/sass_transformer'
  autoload :ScssTransformer,  'condenser/transformers/sass_transformer'
  autoload :EjsTemplare,      'condenser/templating_engine/ejs'
  autoload :JstTransformer,   'condenser/transformers/jst_transformer'
  autoload :FileWriter,       'condenser/writers/file_writer'
  autoload :ZlibWriter,       'condenser/writers/zlib_writer'
  autoload :BrotliWriter,     'condenser/writers/brotli_writer'
  autoload :BuildCache,       'condenser/build_cache'
  
  def self.configure(&block)
    instance_eval(&block)
  end
  
  attr_accessor :logger, :digestor, :base
  
  # base: If base is passed assets cache_keys will be realitve to this.
  #       This allows deploy systems like Capistrano to take advantage of the
  #       cache even though it precompiles assets in a different folder
  def initialize(*path, logger: nil, digestor: nil, cache: nil, pipeline: nil, npm_path: nil, base: nil, &block)
    @logger = logger || Logger.new($stdout, level: :info)
    @path = []
    append_path(path)
    self.npm_path = npm_path
    @base = base
    @cache = cache || Cache::MemoryStore.new
    @build_cc = 0
    self.digestor = digestor || Digest::SHA256

    if block
      configure(&block)
    elsif pipeline != false
      self.configure do
        # register_preprocessor 'application/javascript', Condenser::JSAnalyzer
        register_preprocessor 'application/javascript', Condenser::BabelProcessor
        register_exporter     'application/javascript', Condenser::RollupProcessor
        register_minifier     'application/javascript', Condenser::UglifyMinifier
        
        register_minifier  'text/css', Condenser::SassMinifier
      
        register_writer Condenser::FileWriter.new
        register_writer Condenser::ZlibWriter.new
        if Gem::Specification::find_all_by_name('brotli').any?
          register_writer Condenser::BrotliWriter.new
        end
      end
    end
  end
  
  def configure(&block)
    instance_eval(&block)
  end
end

Condenser.configure do
  # Common asset text types
  register_mime_type 'application/json',  extension: '.json', charset: :unicode
  register_mime_type 'application/ruby',  extension: '.rb'
  register_mime_type 'application/xml',   extension: '.xml'
  register_mime_type 'text/html',         extensions: %w(.html .htm), charset: :html
  register_mime_type 'text/plain',        extensions: %w(.txt .text)
  register_mime_type 'text/yaml',         extensions: %w(.yml .yaml), charset: :unicode

  # Common image types
  register_mime_type 'image/x-icon',      extension: '.ico'
  register_mime_type 'image/bmp',         extension: '.bmp'
  register_mime_type 'image/gif',         extension: '.gif'
  register_mime_type 'image/webp',        extension: '.webp'
  register_mime_type 'image/png',         extension: '.png'
  register_mime_type 'image/jpeg',        extensions: %w(.jpg .jpeg)
  register_mime_type 'image/tiff',        extensions: %w(.tiff .tif)
  register_mime_type 'image/svg+xml',     extension: '.svg'

  # Common audio/video types
  register_mime_type 'video/webm',      extensions: %w(.webm')
  register_mime_type 'audio/basic',     extensions: %w(.snd .au)
  register_mime_type 'audio/aiff',      extensions: %w(.aiff)
  register_mime_type 'audio/mpeg',      extensions: %w(.mp3 .mp2 .m2a .m3a)
  register_mime_type 'application/ogg', extensions: %w(.ogx)
  register_mime_type 'audio/ogg',       extensions: %w(.ogg .oga)
  register_mime_type 'audio/midi',      extensions: %w(.midi .mid)
  register_mime_type 'video/avi',       extensions: %w(.avi)
  register_mime_type 'audio/wave',      extensions: %w(.wav .wave)
  register_mime_type 'video/mp4',       extensions: %w(.mp4 .m4v)
  register_mime_type 'audio/aac',       extensions: %w(.aac)
  register_mime_type 'audio/mp4',       extensions: %w(.m4a)
  register_mime_type 'audio/flac',      extensions: %w(.flac)
  register_mime_type 'video/quicktime', extensions: %w(.mov)

  # Common font types
  register_mime_type 'application/vnd.ms-fontobject', extension: '.eot'
  register_mime_type 'application/x-font-opentype',   extension: '.otf'
  register_mime_type 'application/x-font-ttf',        extension: '.ttf'
  register_mime_type 'application/font-woff',         extension: '.woff'
  register_mime_type 'application/font-woff2',        extension: '.woff2'
  
  # Sourmaps
  register_mime_type 'application/sourcemap', extension: '.map', charset: :unicode
  
  # Web Manifest
  register_mime_type 'application/manifest+json', extension: '.webmanifest', charset: :unicode

  # ERB
  register_mime_type 'application/erb', extension: '.erb'
  register_template  'application/erb', Condenser::Erubi
  
  # CSS
  register_mime_type 'text/css', extension: '.css', charset: :css
  
  # SASS
  register_mime_type 'text/sass', extensions: %w(.sass .css.sass)
  # register_transformer  'text/sass', 'text/css', SassProcessor
  
  # SCSS
  register_mime_type    'text/scss', extensions: %w(.scss .css.scss)
  register_transformer  'text/scss', 'text/css', Condenser::ScssTransformer
  
  # Javascript
  register_mime_type    'application/javascript', extension: '.js', charset: :unicode
  
  # EJS
  register_mime_type 'application/ejs', extensions: '.ejs', charset: :unicode
  register_template  'application/ejs', Condenser::EjsTemplare
  
  # JST
  register_mime_type    'application/jst', extensions: '.jst', charset: :unicode
  register_transformer  'application/jst', 'application/javascript', Condenser::JstTransformer
  
  # Writers
  register_mime_type 'application/gzip',    extensions: %w(.gz .gzip)
  register_mime_type 'application/brotli',  extension: %w(.br)
end