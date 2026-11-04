require 'test_helper'

class ManifestTest < ActiveSupport::TestCase
  
  def setup
    super
    @dir = Dir.mktmpdir
  end
  
  def teardown
    super
    FileUtils.remove_entry(@dir, true)
  end

  test "specify full manifest filename" do
    filename = File.join(@dir, 'manifests', 'assets.json')

    manifest = Condenser::Manifest.new(@env, dir: @dir, filename: filename)

    assert_equal @dir, manifest.dir
    assert_equal filename, manifest.filename
  end

  test "specify manifest directory yields manifest.json" do
    manifest = Condenser::Manifest.new(@env, dir: @dir)

    assert_equal @dir, manifest.dir
    assert_equal File.join(@dir, 'manifest.json'), manifest.filename
  end

  test "dir and filename are expanded" do
    Dir.chdir(@dir) do
      manifest = Condenser::Manifest.new(@env, dir: 'public', filename: 'tmp/manifest.json')

      assert_equal File.join(Dir.pwd, 'public'), manifest.dir
      assert_equal File.join(Dir.pwd, 'tmp/manifest.json'), manifest.filename
    end
  end

  test "must specify manifest directory" do
    assert_raises(ArgumentError) { Condenser::Manifest.new(@env) }
    assert_raises(ArgumentError) { Condenser::Manifest.new(filename: File.join(@dir, 'manifest.json')) }
  end

  test "dir and filename can't be positional" do
    assert_raises(ArgumentError) { Condenser::Manifest.new(@env, @dir) }
    assert_raises(ArgumentError) { Condenser::Manifest.new(@env, @dir, File.join(@dir, 'manifest.json')) }
  end

  test "logger: without an environment" do
    log = StringIO.new
    File.write(File.join(@dir, 'manifest.json'), '{')
    manifest = Condenser::Manifest.new(dir: @dir, logger: Logger.new(log))

    assert_match(/manifest\.json is invalid/, log.string)
  end

  test "logger: with an environment is used instead of the environment's" do
    logger = Logger.new(File::NULL)
    manifest = Condenser::Manifest.new(@env, dir: @dir, logger: logger)
    @env.logger = Logger.new(File::NULL)

    assert_same logger, manifest.logger
  end

  test "logger defaults to the environment's logger" do
    assert_same @env.logger, Condenser::Manifest.new(@env, dir: @dir).logger
  end

  test "logs to the environment's logger at the time it's used" do
    file 'application.js', "console.log(1);\n"
    manifest = Condenser::Manifest.new(@env, dir: @dir)
    log = StringIO.new
    @env.logger = Logger.new(log, level: :debug)

    assert_same @env.logger, manifest.logger
    manifest.compile('application.js')
    assert_match(/application\.js/, log.string)
  end

  test "logger defaults to $stdout without an environment" do
    logger = Condenser::Manifest.new(dir: @dir).logger

    assert_equal $stdout, logger.instance_variable_get(:@logdev).dev
    assert_equal Logger::INFO, logger.level
  end

  test "must specify env to compile assets" do
    manifest = Condenser::Manifest.new(dir: @dir)

    assert_raises Condenser::Error do
      manifest.compile('application.js')
    end
  end

  test "compile asset" do
    file 'application.js', <<-JS
      console.log(1);
    JS
    @env.register_writer Condenser::ZlibWriter.new
    manifest = Condenser::Manifest.new(@env, dir: @dir)

    asset = @env['application.js']
    assert !File.exist?("#{@dir}/#{asset.path}")

    manifest.compile('application.js')
    assert File.directory?(manifest.dir)
    assert File.file?(manifest.filename)

    assert File.exist?("#{@dir}/manifest.json")
    assert File.exist?("#{@dir}/#{asset.path}")
    assert File.exist?("#{@dir}/#{asset.path}.gz")

    data = JSON.parse(File.read(manifest.filename))
    assert data['application.js']
    assert_equal asset.path,  data['application.js']['path']
    assert_equal 15,          data['application.js']['size']
  end

  test "compile returns the files written" do
    file 'application.js', 'console.log(1);'
    @env.register_writer Condenser::ZlibWriter.new
    manifest = Condenser::Manifest.new(@env, dir: @dir)

    path = @env.find('application.js').export.path
    assert_equal [path, "#{path}.gz"], manifest.compile('application.js')
  end

  test "compile doesn't return files skipped because they're already written" do
    file 'application.js', 'console.log(1);'
    @env.register_writer Condenser::ZlibWriter.new
    manifest = Condenser::Manifest.new(@env, dir: @dir)
    path = @env.find('application.js').export.path
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "#{path}.gz"), 'existing')

    assert_equal [path], manifest.compile('application.js')
    assert_equal [], manifest.compile('application.js')
  end

  test "compile asset dependencies includes the dependencies" do
    file 'foo.svg', <<-SVG
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path d="M6 18L18 6M6 6l12 12" />
      </svg>
    SVG
    
    file 'test.scss', <<-SCSS
      body {
        background: asset-url("foo.svg");
      }
    SCSS
    
    manifest = Condenser::Manifest.new(@env, dir: @dir)

    main_digest_path = @env['test.css'].path
    dep_digest_path = @env['foo.svg'].path

    assert !File.exist?("#{@dir}/#{main_digest_path}")
    assert !File.exist?("#{@dir}/#{dep_digest_path}")

    manifest.compile('test.css')
    assert File.directory?(manifest.dir)
    assert File.file?(manifest.filename)

    assert File.exist?("#{@dir}/manifest.json")
    assert File.exist?("#{@dir}/#{main_digest_path}")
    assert File.exist?("#{@dir}/#{dep_digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert_equal main_digest_path, data['test.css']['path']
    assert_equal dep_digest_path, data['foo.svg']['path']
  end
  
  # TODO:
  # test "compile asset with aliased index links" do
  #   manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))
  #
  #   main_digest_path = @env['alias-index-link.js'].path
  #   dep_digest_path = @env['coffee.js'].path
  #
  #   assert !File.exist?("#{@dir}/#{main_digest_path}")
  #   assert !File.exist?("#{@dir}/#{dep_digest_path}")
  #
  #   manifest.compile('alias-index-link.js')
  #   assert File.directory?(manifest.dir)
  #   assert File.file?(manifest.filename)
  #
  #   assert File.exist?("#{@dir}/manifest.json")
  #   assert File.exist?("#{@dir}/#{main_digest_path}")
  #   assert File.exist?("#{@dir}/#{dep_digest_path}")
  #
  #   data = JSON.parse(File.read(manifest.filename))
  #
  #   assert data['files'][main_digest_path]
  #   assert data['files'][dep_digest_path]
  #   assert_equal "alias-index-link.js", data['files'][main_digest_path]['logical_path']
  #   assert_equal "coffee.js", data['files'][dep_digest_path]['logical_path']
  #   assert_equal main_digest_path, data['assets']['alias-index-link.js']
  #   assert_equal dep_digest_path, data['assets']['coffee.js']
  # end
  #
  test "compile to directory and seperate location" do
    file 'application.js', <<-JS
      console.log(1);
    JS

    root  = File.join(Dir::tmpdir, 'public')
    dir   = File.join(root, 'assets')
    path  = File.join(root, 'manifests', 'manifest-123.json')

    FileUtils.remove_entry(root, true)

    assert !File.exist?(root)
    manifest = Condenser::Manifest.new(@env, dir: dir, filename: path)

    manifest.compile('application.js')
    assert File.directory?(manifest.dir)
    assert File.file?(path)
    FileUtils.remove_entry(root, true)
  end

  # TODO:
  # test "compile asset with absolute path" do
  #   manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))
  #
  #   digest_path = @env['gallery.js'].path
  #
  #   assert !File.exist?("#{@dir}/#{digest_path}")
  #
  #   manifest.compile(fixture_path('default/gallery.js'))
  #
  #   assert File.exist?("#{@dir}/manifest.json")
  #   assert File.exist?("#{@dir}/#{digest_path}")
  #
  #   data = JSON.parse(File.read(manifest.filename))
  #   assert data['files'][digest_path]
  #   assert_equal digest_path, data['assets']['gallery.js']
  # end

  test "compile logs one summary line at info and the per-file lines at debug" do
    file 'application.js', "console.log(1);\n"
    file 'gallery.css', "body { color: red; }\n"
    log = StringIO.new
    @env.logger = Logger.new(log, level: :debug)
    manifest = Condenser::Manifest.new(@env, dir: @dir)

    manifest.compile('application.js', 'gallery.css')
    files = Dir.children(@dir).size - 1
    info = log.string.lines.grep_v(/\AD, /)
    assert_equal 1, info.size, log.string
    assert_match(/\AI, .* INFO -- : Processed 2 assets \(#{files} files written\) in \d+\.\ds$/, info[0])
    assert_match(/^D, .* DEBUG -- : Writing application-\w+\.js$/, log.string)
    assert_match(/^D, .* DEBUG -- : Minifying gallery\.css with /, log.string)

    log.truncate(0)
    log.rewind
    manifest.export('application.js')
    assert_match(/\AI, .* INFO -- : Processed 1 asset \(\d+ files? written\) in \d+\.\ds$/, log.string.lines.grep_v(/\AD, /).join)
  end

  test "compile multiple assets" do
    file 'application.js', <<-JS
      console.log(1);
    JS
    
    file 'gallery.css', <<-CSS
      * { color: green }
    CSS
    
    manifest = Condenser::Manifest.new(@env, dir: @dir)

    app_digest_path = @env.find_export('application.js').path
    gallery_digest_path = @env.find_export('gallery.css').path

    assert !File.exist?("#{@dir}/#{app_digest_path}")
    assert !File.exist?("#{@dir}/#{gallery_digest_path}")

    manifest.compile('application.js', 'gallery.css')

    assert File.exist?("#{@dir}/manifest.json")
    assert File.exist?("#{@dir}/#{app_digest_path}")
    assert File.exist?("#{@dir}/#{gallery_digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert data['application.js']
    assert data['gallery.css']
    assert_equal app_digest_path, data['application.js']['path']
    assert_equal gallery_digest_path, data['gallery.css']['path']
  end

  # TODO:
  # test "compile with transformed asset" do
  #   assert svg_digest_path = @env['logo.svg'].path
  #   assert png_digest_path = @env['logo.png'].path
  #
  #   assert !File.exist?("#{@dir}/#{svg_digest_path}")
  #   assert !File.exist?("#{@dir}/#{png_digest_path}")
  #
  #   manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))
  #   manifest.compile('logo.svg', 'logo.png')
  #
  #   assert File.exist?("#{@dir}/manifest.json")
  #   assert File.exist?("#{@dir}/#{svg_digest_path}")
  #   assert File.exist?("#{@dir}/#{png_digest_path}")
  #
  #   data = JSON.parse(File.read(manifest.filename))
  #   assert data['files'][svg_digest_path]
  #   assert data['files'][png_digest_path]
  #   assert_equal svg_digest_path, data['assets']['logo.svg']
  #   assert_equal png_digest_path, data['assets']['logo.png']
  # end

  # TODO:
  # test "compile asset with links" do
  #   manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))
  #
  #   main_digest_path = @env['gallery-link.js'].path
  #   dep_digest_path  = @env['gallery.js'].path
  #
  #   assert !File.exist?("#{@dir}/#{main_digest_path}")
  #   assert !File.exist?("#{@dir}/#{dep_digest_path}")
  #
  #   manifest.compile('gallery-link.js')
  #   assert File.directory?(manifest.dir)
  #   assert File.file?(manifest.filename)
  #
  #   assert File.exist?("#{@dir}/manifest.json")
  #   assert File.exist?("#{@dir}/#{main_digest_path}")
  #   assert File.exist?("#{@dir}/#{dep_digest_path}")
  #
  #   data = JSON.parse(File.read(manifest.filename))
  #   assert data['files'][main_digest_path]
  #   assert data['files'][dep_digest_path]
  #   assert_equal "gallery-link.js", data['files'][main_digest_path]['logical_path']
  #   assert_equal "gallery.js", data['files'][dep_digest_path]['logical_path']
  #   assert_equal main_digest_path, data['assets']['gallery-link.js']
  #   assert_equal dep_digest_path, data['assets']['gallery.js']
  # end

  # TODO:
  # test "compile nested asset with links" do
  #   manifest = Sprockets::Manifest.new(@env, File.join(@dir, 'manifest.json'))
  #
  #   main_digest_path   = @env['explore-link.js'].path
  #   dep_digest_path    = @env['gallery-link.js'].path
  #   subdep_digest_path = @env['gallery.js'].path
  #
  #   assert !File.exist?("#{@dir}/#{main_digest_path}")
  #   assert !File.exist?("#{@dir}/#{dep_digest_path}")
  #   assert !File.exist?("#{@dir}/#{subdep_digest_path}")
  #
  #   manifest.compile('explore-link.js')
  #   assert File.directory?(manifest.dir)
  #   assert File.file?(manifest.filename)
  #
  #   assert File.exist?("#{@dir}/manifest.json")
  #   assert File.exist?("#{@dir}/#{main_digest_path}")
  #   assert File.exist?("#{@dir}/#{dep_digest_path}")
  #   assert File.exist?("#{@dir}/#{subdep_digest_path}")
  #
  #   data = JSON.parse(File.read(manifest.filename))
  #   assert data['files'][main_digest_path]
  #   assert data['files'][dep_digest_path]
  #   assert data['files'][subdep_digest_path]
  #   assert_equal "explore-link.js", data['files'][main_digest_path]['logical_path']
  #   assert_equal "gallery-link.js", data['files'][dep_digest_path]['logical_path']
  #   assert_equal "gallery.js", data['files'][subdep_digest_path]['logical_path']
  #   assert_equal main_digest_path, data['assets']['explore-link.js']
  #   assert_equal dep_digest_path, data['assets']['gallery-link.js']
  #   assert_equal subdep_digest_path, data['assets']['gallery.js']
  # end

  test "recompile asset" do
    file 'application.js', "console.log(1);"

    manifest = Condenser::Manifest.new(@env, dir: @dir)

    digest_path = @env['application.js'].path
    assert !File.exist?("#{@dir}/#{digest_path}"), Dir["#{@dir}/*"].inspect

    manifest.compile('application.js')

    assert File.exist?("#{@dir}/manifest.json")
    assert File.exist?("#{@dir}/#{digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert data['application.js']
    assert_equal digest_path, data['application.js']['path']

    File.write(File.join(@path, 'application.js'), "console.log(2);")
    sleep 0.25 if @env.build_cache.listening

    new_digest_path = @env['application.js'].path
    assert_not_equal new_digest_path, digest_path

    manifest.compile('application.js')

    assert File.exist?("#{@dir}/manifest.json")
    assert File.exist?("#{@dir}/#{digest_path}")
    assert File.exist?("#{@dir}/#{new_digest_path}")

    data = JSON.parse(File.read(manifest.filename))
    assert data['application.js']
    assert_equal new_digest_path, data['application.js']['path']
  end

  test "test manifest does not exist" do
    file 'application.js', "console.log(1);"

    assert !File.exist?("#{@dir}/manifest.json")

    manifest = Condenser::Manifest.new(@env, dir: @dir)
    manifest.compile('application.js')

    assert File.exist?("#{@dir}/manifest.json")
    data = JSON.parse(File.read(manifest.filename))
    assert data['application.js']
  end

  test "test blank manifest" do
    file 'application.js', "console.log(1);"

    assert !File.exist?("#{@dir}/manifest.json")

    FileUtils.mkdir_p(@dir)
    File.write("#{@dir}/manifest.json", '{}')
    assert_equal "{}", File.read("#{@dir}/manifest.json")

    manifest = Condenser::Manifest.new(@env, dir: @dir)
    manifest.compile('application.js')

    assert File.exist?("#{@dir}/manifest.json")
    data = JSON.parse(File.read(manifest.filename))
    assert data['application.js']
  end

  test "test skip invalid manifest" do
    file 'application.js', "console.log(1);"

    assert !File.exist?("#{@dir}/manifest.json")

    FileUtils.mkdir_p(@dir)
    File.write("#{@dir}/manifest.json", "not valid json;")
    assert_equal "not valid json;", File.read("#{@dir}/manifest.json")

    log = StringIO.new
    @env.logger = Logger.new(log)
    manifest = Condenser::Manifest.new(@env, dir: @dir)
    assert_match(/manifest\.json is invalid/, log.string)
    manifest.compile('application.js')

    assert File.exist?("#{@dir}/manifest.json")
    data = JSON.parse(File.read(manifest.filename))
    assert data['application.js']
  end

  test "nil environment raises compilation error" do
    assert !File.exist?("#{@dir}/manifest.json")

    manifest = Condenser::Manifest.new(nil, dir: @dir)
    assert_raises Condenser::Error do
      manifest.compile('application.js')
    end
  end

  test "no environment raises compilation error" do
    assert !File.exist?("#{@dir}/manifest.json")

    manifest = Condenser::Manifest.new(dir: @dir)
    assert_raises Condenser::Error do
      manifest.compile('application.js')
    end
  end

  # TODO:
  # test "find_sources with environment" do
  #   manifest = Sprockets::Manifest.new(@env, @dir)
  #
  #   result = manifest.find_sources("mobile/a.js", "mobile/b.js")
  #   assert_equal ["var A;\n", "var B;\n"], result.to_a.sort
  #
  #   result = manifest.find_sources("not_existent.js", "also_not_existent.js")
  #   assert_equal [], result.to_a
  #
  #   result = manifest.find_sources("mobile/a.js", "also_not_existent.js")
  #   assert_equal ["var A;\n"], result.to_a
  # end

  # TODO:
  # test "find_sources without environment" do
  #   manifest = Sprockets::Manifest.new(@env, @dir)
  #   manifest.compile('mobile/a.js', 'mobile/b.js')
  #
  #   manifest = Sprockets::Manifest.new(nil, @dir)
  #
  #   result = manifest.find_sources("mobile/a.js", "mobile/b.js")
  #   assert_equal ["var A;\n", "var B;\n"], result.to_a
  #
  #   result = manifest.find_sources("not_existent.js", "also_not_existent.js")
  #   assert_equal [], result.to_a
  #
  #   result = manifest.find_sources("mobile/a.js", "also_not_existent.js")
  #   assert_equal ["var A;\n"], result.to_a
  # end

  test "compress non-binary assets" do
    file 'gallery.css', '* { background: green; }'
    file 'application.js', 'x'
    file 'logo.svg', 'x'
    file 'favicon.ico', 'x'

    @env.register_writer Condenser::ZlibWriter.new
    manifest = Condenser::Manifest.new(@env, dir: @dir)
    %W{ gallery.css application.js logo.svg favicon.ico }.each do |file_name|
      original_path = @env[file_name].path
      manifest.compile(file_name)
      assert File.exist?("#{@dir}/#{original_path}.gz"), "Expecting '#{original_path}' to generate gzipped file: '#{original_path}.gz' but it did not"
    end
  end

  # TODO:
  # test "writes gzip files even if files were already on disk" do
  #   @env.gzip = false
  #   manifest = Sprockets::Manifest.new(@env, @dir)
  #   files = %W{ gallery.css application.js logo.svg favicon.ico}
  #   files.each do |file_name|
  #     original_path = @env[file_name].path
  #     manifest.compile(file_name)
  #     assert File.exist?("#{@dir}/#{original_path}"), "Expecting '#{@dir}/#{original_path}' to exist but did not"
  #   end
  #
  #   @env.gzip = true
  #   files.each do |file_name|
  #     original_path = @env[file_name].path
  #     manifest.compile(file_name)
  #     assert File.exist?("#{@dir}/#{original_path}.gz"), "Expecting '#{original_path}' to generate gzipped file: '#{original_path}.gz' but it did not"
  #   end
  # end

  # TODO:
  # test "disable file gzip" do
  #   @env.gzip = false
  #   manifest = Sprockets::Manifest.new(@env, @dir)
  #   %W{ gallery.css application.js logo.svg favicon.ico }.each do |file_name|
  #     original_path = @env[file_name].path
  #     manifest.compile(file_name)
  #     refute File.exist?("#{@dir}/#{original_path}.gz"), "Expecting '#{original_path}' to not generate gzipped file: '#{original_path}.gz' but it did"
  #   end
  # end

  test "do not compress binary assets" do
    file 'blank.gif', Random.new.bytes(128)

    manifest = Condenser::Manifest.new(@env, dir: @path)
    %W{ blank.gif }.each do |file_name|
      original_path = @env[file_name].path
      manifest.compile(file_name)
      refute File.exist?("#{@path}/#{original_path}.gz"), "Expecting '#{original_path}' to not generate gzipped file: '#{original_path}.gz' but it did"
    end
  end

  # TODO:
  # test 'raises exception when gzip fails' do
  #   manifest = Sprockets::Manifest.new(@env, @dir)
  #   Zlib::GzipWriter.stub(:new, -> (io, level) { fail 'kaboom' }) do
  #     ex = assert_raises(RuntimeError) { manifest.compile('application.js') }
  #     assert_equal 'kaboom', ex.message
  #   end
  # end
  #
  # # Sleep duration to context switch between concurrent threads.
  # CONTEXT_SWITCH_DURATION = 0.1
  #
  # # Record Exporter sequence with a delay to test concurrency.
  # class SlowExporter < Sprockets::Exporters::Base
  #   class << self
  #     attr_accessor :seq
  #   end
  #
  #   def call
  #     SlowExporter.seq << '0'
  #     sleep CONTEXT_SWITCH_DURATION
  #     SlowExporter.seq << '1'
  #   end
  # end
  #
  # class SlowExporter2 < SlowExporter
  # end
  #
  # test 'concurrent exporting' do
  #   # Register 2 exporters and compile 2 files to ensure that
  #   # all 4 exporting tasks run concurrently.
  #   SlowExporter.seq = []
  #   @env.register_exporter 'image/png',SlowExporter
  #   @env.register_exporter 'image/png',SlowExporter2
  #   Sprockets::Manifest.new(@env, @dir).compile('logo.png', 'troll.png')
  #   refute_equal %w(0 1 0 1 0 1 0 1), SlowExporter.seq
  # end
  #
  # test 'sequential exporting' do
  #   @env.export_concurrent = false
  #   SlowExporter.seq = []
  #   @env.register_exporter 'image/png',SlowExporter
  #   @env.register_exporter 'image/png',SlowExporter2
  #   Sprockets::Manifest.new(@env, @dir).compile('logo.png', 'troll.png')
  #   assert_equal %w(0 1 0 1 0 1 0 1), SlowExporter.seq
  # end
  #
  # # Record Processor sequence with a delay to test concurrency.
  # class SlowProcessor
  #   attr_reader :seq
  #
  #   def initialize
  #     @seq = []
  #   end
  #
  #   def call(_)
  #     seq << '0'
  #     sleep CONTEXT_SWITCH_DURATION
  #     seq << '1'
  #     nil
  #   end
  # end
  #
  # test 'concurrent processing' do
  #   processor = SlowProcessor.new
  #   @env.register_postprocessor 'image/png', processor
  #   Sprockets::Manifest.new(@env, @dir).compile('logo.png', 'troll.png')
  #   refute_equal %w(0 1 0 1), processor.seq
  # end
  #
  # test 'sequential processing' do
  #   @env.export_concurrent = false
  #   processor = SlowProcessor.new
  #   @env.register_postprocessor 'image/png', processor
  #   Sprockets::Manifest.new(@env, @dir).compile('logo.png', 'troll.png')
  #   assert_equal %w(0 1 0 1), processor.seq
  # end

  test "javascript types are in the manifest" do
    file 'application.js', <<-JS
      console.log(1);
    JS
    
    manifest = Condenser::Manifest.new(@env, dir: @dir)
    manifest.compile('application.js')
    assert File.directory?(manifest.dir)
    assert File.file?(manifest.filename)
    assert File.exist?("#{@dir}/manifest.json")
    
    data = JSON.parse(File.read(manifest.filename))
    assert data['application.js']
    assert_equal "module",    data['application.js']['type']
  end

  # Counts Dir.each_child calls per directory while Thread.current[:dir_reads]
  # is set.
  module CountDirReads
    def each_child(dir, *args, **kwargs, &block)
      Thread.current[:dir_reads][File.expand_path(dir)] += 1 if Thread.current[:dir_reads]
      super
    end
  end
  Dir.singleton_class.prepend(CountDirReads)

  def write_output(path)
    path = File.join(@dir, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, 'x')
  end

  def write_manifest(data, filename = File.join(@dir, 'manifest.json'))
    FileUtils.mkdir_p(File.dirname(filename))
    File.write(filename, JSON.generate(data))
    Condenser::Manifest.new(dir: @dir, filename: filename)
  end

  def output_files
    Dir.glob('**/*', File::FNM_DOTMATCH, base: @dir).reject { |f| File.basename(f) == '.' }.sort
  end

  test "clean keeps the current assets and their compressed versions" do
    manifest = write_manifest({
      'application.js' => { path: 'application-abc.js' },
      'application.css' => { path: 'application-def.css', sourcemap: 'application-def.css.map' }
    })
    %w(application-abc.js application-abc.js.gz application-abc.js.br
       application-def.css application-def.css.gz application-def.css.map).each do |f|
      write_output(f)
    end

    manifest.clean

    assert_equal %w(application-abc.js application-abc.js.br application-abc.js.gz
                    application-def.css application-def.css.gz application-def.css.map
                    manifest.json), output_files
  end

  test "clean keeps current assets in nested directories" do
    manifest = write_manifest({
      'admin/application.js' => { path: 'admin/application-abc.js' },
      'admin/pages/show.js' => { path: 'admin/pages/show-def.js', sourcemap: 'admin/pages/show-def.js.map' }
    })
    %w(admin/application-abc.js admin/application-abc.js.gz
       admin/pages/show-def.js admin/pages/show-def.js.br admin/pages/show-def.js.map).each do |f|
      write_output(f)
    end

    manifest.clean

    assert_equal %w(admin admin/application-abc.js admin/application-abc.js.gz
                    admin/pages admin/pages/show-def.js admin/pages/show-def.js.br
                    admin/pages/show-def.js.map manifest.json), output_files
  end

  test "clean keeps files named after a current asset with extra extensions" do
    manifest = write_manifest({ 'application.js' => { path: 'application-abc.js' } })
    %w(application-abc.js application-abc.js.xz application-abc.js.zst
       application-abc.js.map application-abc.js.map.gz).each { |f| write_output(f) }

    manifest.clean

    assert_equal %w(application-abc.js application-abc.js.map application-abc.js.map.gz
                    application-abc.js.xz application-abc.js.zst manifest.json), output_files
  end

  test "clean removes files that only share a current asset's stem" do
    manifest = write_manifest({ 'admin/application.js' => { path: 'admin/application-abc.js' } })
    %w(admin/application-abc.js admin/application-old.js.xz admin/application-abc.jsx
       admin/application-abc admin/application-abc.js.d/a.js admin/.gz).each { |f| write_output(f) }

    manifest.clean

    assert_equal %w(admin admin/application-abc.js manifest.json), output_files
  end

  test "clean removes files that aren't in the manifest" do
    manifest = write_manifest({ 'application.js' => { path: 'application-abc.js' } })
    write_output('application-abc.js')
    write_output('application-old.js')
    write_output('application-old.js.gz')

    manifest.clean
    assert_equal %w(application-abc.js manifest.json), output_files
  end

  test "clean removes old files in nested directories and directories left empty" do
    manifest = write_manifest({ 'admin/application.js' => { path: 'admin/application-abc.js' } })
    write_output('admin/application-abc.js')
    write_output('admin/application-old.js')
    write_output('admin/old/a/b/c-old.js')
    write_output('admin/new/a-new.js')
    write_output('stale/a/b/c-old.js')
    FileUtils.mkdir_p(File.join(@dir, 'empty/a'))

    manifest.clean

    assert_equal %w(admin admin/application-abc.js manifest.json), output_files
  end

  test "clean doesn't remove the manifest" do
    manifest = write_manifest({ 'application.js' => { path: 'application-abc.js' } },
      File.join(@dir, '.manifests', 'manifest-123.json'))
    write_output('application-abc.js')

    manifest.clean

    assert_equal %w(.manifests .manifests/manifest-123.json application-abc.js), output_files
  end

  test "clean doesn't remove files outside the output directory" do
    outside = Dir.mktmpdir
    write_output('application-old.js')
    File.write(File.join(outside, 'other.js'), 'x')
    File.symlink(outside, File.join(@dir, 'linked'))
    manifest = write_manifest({}, File.join(outside, 'manifest.json'))

    manifest.clean

    assert_equal %w(linked), output_files
    assert File.exist?(File.join(outside, 'other.js'))
    assert File.exist?(File.join(outside, 'manifest.json'))
  ensure
    FileUtils.remove_entry(outside, true)
  end

  test "clean reads each directory once" do
    manifest = write_manifest({ 'a/b/c/current.js' => { path: 'a/b/c/current-abc.js' } })
    %w(a b c d).each_with_index do |_, i|
      dir = %w(a b c d).first(i + 1).join('/')
      write_output("#{dir}/old.js")
      write_output("#{dir}/sibling/old.js")
    end
    write_output('a/b/c/current-abc.js')

    Thread.current[:dir_reads] = Hash.new(0)
    manifest.clean
    reads = Thread.current[:dir_reads]

    assert_equal [1], reads.values.uniq, reads.inspect
    assert_equal File.expand_path(@dir), reads.keys.min_by(&:size)
    assert_equal %w(a a/b a/b/c a/b/c/current-abc.js manifest.json), output_files
  ensure
    Thread.current[:dir_reads] = nil
  end

  test "clean after recompiling removes the previous version" do
    file 'application.js', "console.log(1);"
    manifest = Condenser::Manifest.new(@env, dir: @dir)
    manifest.compile('application.js')
    old_path = @env['application.js'].path

    File.write(File.join(@path, 'application.js'), "console.log(2);")
    sleep 0.25 if @env.build_cache.listening
    new_path = @env['application.js'].path
    assert_not_equal old_path, new_path
    manifest.compile('application.js')

    Condenser::Manifest.new(dir: @dir).clean

    assert_includes output_files, new_path
    assert_includes output_files, 'manifest.json'
    assert_empty output_files.select { |f| f.start_with?(old_path) }
    assert_empty output_files.reject { |f| f == 'manifest.json' || f.start_with?(new_path) }
  end

  test "clobber removes the manifest and everything in the output directory" do
    manifest = write_manifest({ 'admin/application.js' => { path: 'admin/application-abc.js' } })
    write_output('admin/application-abc.js')
    write_output('application-old.js')

    manifest.clobber

    assert File.directory?(@dir)
    assert_equal [], output_files
  end
end
