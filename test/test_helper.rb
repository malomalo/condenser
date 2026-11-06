# To make testing/debugging easier, test within this source tree versus an
# installed gem
$LOAD_PATH << File.expand_path('../lib', __FILE__)

require 'simplecov'
SimpleCov.start do
  add_group 'lib', 'condenser/lib'
  add_group 'ext', 'condenser/ext'
end

require 'fileutils'
require 'json'

require 'condenser'
require 'condenser/server'
require 'condenser/cache/memory_store'

require 'byebug'
require "active_support"
require "minitest/autorun"
require "active_support/test_case"
require 'mocha/minitest'
require 'minitest/reporters'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

# The tests install the npm packages they use into tmp/ as needed, unpinned.
# These are installed first, at these versions, so a new release doesn't
# change the test output. Babel is at the major condenser installs, so a
# tmp/ from before doesn't keep testing an older one. They're saved to
# tmp/package.json so later installs don't replace them. To upgrade, bump the
# version here.
TEST_NPM_PACKAGES = {
  'rolldown'                        => '1.2.15',
  '@babel/core'                     => '8',
  '@babel/preset-env'               => '8',
  '@babel/plugin-transform-runtime' => '8'
}

TEST_NPM_DIR = File.expand_path('../../tmp', __FILE__)

def install_test_npm_packages
  FileUtils.mkdir_p(TEST_NPM_DIR)
  missing = TEST_NPM_PACKAGES.reject do |name, version|
    manifest = File.join(TEST_NPM_DIR, 'node_modules', name, 'package.json')
    next false unless File.exist?(manifest)
    installed = JSON.parse(File.read(manifest))['version']
    installed == version || installed.start_with?("#{version}.")
  end
  return if missing.empty?

  packages = missing.map { |name, version| "#{name}@#{version}" }
  system("npm", "install", "--silent", "--save-exact", "--prefix", TEST_NPM_DIR, *packages) ||
    abort("npm install #{packages.join(' ')} failed")
end
install_test_npm_packages

# Decodes a source map's "mappings", for the JavaScript and CSS source map
# tests.
module SourcemapHelpers

  BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

  # Decodes the "mappings" into lines of [column, source, line, column]
  # segments, all 0-based.
  def decode_mappings(mappings)
    source = line = column = 0
    mappings.split(';', -1).map do |generated|
      generated_column = 0
      generated.split(',').map do |segment|
        values = []
        value = shift = 0
        segment.each_char do |char|
          digit = BASE64.index(char)
          value += (digit & 31) << shift
          if digit & 32 == 0
            values << (value.odd? ? -(value >> 1) : value >> 1)
            value = shift = 0
          else
            shift += 5
          end
        end
        generated_column += values[0]
        next [generated_column] if values.size < 4
        source += values[1]
        line += values[2]
        column += values[3]
        [generated_column, source, line, column]
      end
    end
  end

  # The [source, line, column] (0-based) that +needle+ in +code+ maps back to.
  def original_position(code, map, needle)
    index = code.index(needle)
    assert index, "#{needle.inspect} isn't in the bundle"
    line = code[0...index].count("\n")
    line_start = index == 0 ? 0 : (code.rindex("\n", index - 1)&.+(1) || 0)
    column = index - line_start
    segment = decode_mappings(map['mappings'])[line].select { |s| s[0] <= column }.last
    assert segment && segment.size >= 4, "#{needle.inspect} isn't mapped"
    [map['sources'][segment[1]], segment[2], segment[3]]
  end

end

class ActiveSupport::TestCase

  def setup
    @path = File.realpath(Dir.mktmpdir)
    @npm_dir = TEST_NPM_DIR
    Dir.mkdir(@npm_dir) if !Dir.exist?(@npm_dir)
    @env = Condenser.new(@path, logger: Logger.new('/dev/null', level: :debug), npm_path: @npm_dir, base: @path)
    @env.unregister_writer(Condenser::ZlibWriter)
    @env.unregister_writer(Condenser::BrotliWriter)
    @env.context_class.class_eval do
      def asset_path(path, options = {})
        path = environment.find!(path, options).path
        "/assets/#{path}"
      end
    end
  end

  def teardown
    Condenser::NodeWorker.stop_workers
    FileUtils.remove_entry(@path, true)
  end
  
  def assert_json(json, &block)
    assert_equal json, jbuild(&block)
  end
  
  def file(name, source, base: nil)
    base ||= @path
    dir = name.include?('/') ? File.join(base, File.dirname(name)) : base
    path = File.join(base, name)
    
    FileUtils.mkdir_p(dir)
    if File.exist?(path)
      stat = Time.now.to_f - File.stat(path).mtime.to_f
      sleep(1 - stat) if stat < 1
    end
    File.write(path, source)
    sleep 0.25 if @env.build_cache.listening
  end
  
  # Waits for the listener, which is asynchronous, until the block is truthy
  # or +timeout+ seconds have passed.
  def wait_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until (result = yield)
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    result
  end

  def rm(name)
    File.delete(File.join(@path, name))
  end
  
  def assert_file(path, mime_types, source=nil)
    sleep 0.25 if @env.build_cache.listening
    asset = @env.find(path)
    assert asset, "Couldn't find asset \"#{path}\""
    asset.process
    assert_equal path.delete_prefix('/'),     asset.filename
    assert_equal Array(mime_types),           asset.content_types
    assert_equal(source.rstrip, asset.source.rstrip) if !source.nil?
    asset
  end
  
  def assert_exported_file(path, mime_types, source=nil)
    sleep 0.25 if @env.build_cache.listening
    asset = @env.find(path)
    assert asset, "Couldn't find asset \"#{path}\""
    asset = asset.export
    assert_equal path,                        asset.filename
    assert_equal Array(mime_types),           asset.content_types
    assert_equal(source.rstrip, asset.source.rstrip) if !source.nil?
    asset
  end

end
