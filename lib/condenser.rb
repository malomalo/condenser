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
  include Environment, Pipeline, Resolve
  
  def self.configure(&block)
    instance_eval(&block)
  end
  
  attr_reader :logger
  attr_accessor :digestor
  
  def initialize(*path, digestor: nil, cache: nil)
    super()
    @logger = Logger.new($stderr, level: :warn)
    @path = []
    @npm_path = nil
    append_path(path)
    append_path(EJS::ASSET_DIR)
    @cache = cache || Cache::MemoryStore.new
    self.digestor = digestor || Digest::SHA256
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
  register_mime_type 'video/webm', extensions: ['.webm']
  register_mime_type 'audio/basic', extensions: ['.snd', '.au']
  register_mime_type 'audio/aiff', extensions: ['.aiff']
  register_mime_type 'audio/mpeg', extensions: ['.mp3', '.mp2', '.m2a', '.m3a']
  register_mime_type 'application/ogg', extensions: ['.ogx']
  register_mime_type 'audio/ogg', extensions: ['.ogg', '.oga']
  register_mime_type 'audio/midi', extensions: ['.midi', '.mid']
  register_mime_type 'video/avi', extensions: ['.avi']
  register_mime_type 'audio/wave', extensions: ['.wav', '.wave']
  register_mime_type 'video/mp4', extensions: ['.mp4', '.m4v']
  register_mime_type 'audio/aac', extensions: ['.aac']
  register_mime_type 'audio/mp4', extensions: ['.m4a']
  register_mime_type 'audio/flac', extensions: ['.flac']
  register_mime_type 'video/quicktime', extensions: ['.mov']

  # Common font types
  register_mime_type 'application/vnd.ms-fontobject', extensions: ['.eot']
  register_mime_type 'application/x-font-opentype', extensions: ['.otf']
  register_mime_type 'application/x-font-ttf', extensions: ['.ttf']
  register_mime_type 'application/font-woff', extensions: ['.woff']
  register_mime_type 'application/font-woff2', extensions: ['.woff2']
  
  # Sourmaps
  register_mime_type 'application/sourcemap', extension: '.map', charset: :unicode
  
  # ERB
  require 'condenser/templating_engine/erb'
  register_mime_type 'application/erb', extension: '.erb'
  register_template  'application/erb', Condenser::Erubi
  
  # CSS
  require 'condenser/minifiers/sass_minifier'
  register_mime_type      'text/css', extension: '.css', charset: :css
  register_minifier       'text/css', Condenser::SassMinifier
  
  # SASS
  require 'condenser/analyzers/sass_analyzer'
  require 'condenser/transformers/sass_transformer'
  register_mime_type    'text/sass', extensions: %w(.sass .css.sass)
  register_analyzer     'text/sass', Condenser::SassAnalyzer
  # register_transformer  'text/sass', 'text/css', SassProcessor
  
  # SCSS
  register_mime_type    'text/scss', extensions: %w(.scss .css.scss)
  register_analyzer     'text/scss', Condenser::ScssAnalyzer
  register_transformer  'text/scss', 'text/css', Condenser::ScssTransformer
  
  # Javascript
  require 'condenser/analyzers/javascript_analyzer'
  require 'condenser/processors/rollup_processor'
  require 'condenser/processors/babel_processor'
  require 'condenser/minifiers/uglify_minifier'
  register_mime_type    'application/javascript', extension: '.js', charset: :unicode
  register_analyzer     'application/javascript', Condenser::JavascriptAnalyzer
  register_preprocessor 'application/javascript', Condenser::BabelProcessor
  register_exporter     'application/javascript', Condenser::RollupProcessor
  register_minifier     'application/javascript', Condenser::UglifyMinifier

  # EJS
  require 'condenser/transformers/ejs'
  register_mime_type    'application/ejs', extensions: %w(.ejs .jst.ejs)
  register_transformer  'application/ejs', 'application/javascript', Condenser::EjsTransformer
  
  # Writers
  require 'condenser/writers/file_writer'
  require 'condenser/writers/zlib_writer'
  register_mime_type 'application/gzip', extensions: %w(.gz .gzip)
  # register_compressor 'application/gzip', Condenser::Erubi
  register_writer '*/*', Condenser::FileWriter.new
  register_writer Condenser::ZlibWriter::COMPRESSALBE_TYPES, Condenser::ZlibWriter.new, 'application/gzip'
end