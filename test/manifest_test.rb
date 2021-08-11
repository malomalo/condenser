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
    directory = Dir::tmpdir
    filename  = File.join(directory, 'manifest.json')

    manifest = Condenser::Manifest.new(@env, filename)

    assert_equal directory, manifest.dir
    assert_equal filename,  manifest.filename
  end

  test "specify manifest directory yields manifest.json" do
    manifest = Condenser::Manifest.new(@env, @dir)

    assert_equal @dir, manifest.dir
    assert_match('manifest.json', File.basename(manifest.filename))
  end

  test "must specify manifest directory or filename" do
    assert_raises ArgumentError do
      Condenser::Manifest.new(@env)
    end
  end

  test "must specify env to compile assets" do
    manifest = Condenser::Manifest.new(@dir)

    assert_raises Condenser::Error do
      manifest.compile('application.js')
    end
  end

  test "compile asset" do
    file 'application.js', <<-JS
      console.log(1);
    JS
    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))

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
    assert data['application.js']['size'] > 16
    assert_equal asset.path, data['application.js']['path']
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
    
    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))

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
    puts data.inspect
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
    manifest = Condenser::Manifest.new(@env, dir, path)

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

  test "compile multiple assets" do
    file 'application.js', <<-JS
      console.log(1);
    JS
    
    file 'gallery.css', <<-CSS
      * { color: green }
    CSS
    
    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))

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

    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))

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

    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))
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

    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))
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

    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))
    manifest.compile('application.js')

    assert File.exist?("#{@dir}/manifest.json")
    data = JSON.parse(File.read(manifest.filename))
    assert data['application.js']
  end

  test "nil environment raises compilation error" do
    assert !File.exist?("#{@dir}/manifest.json")

    manifest = Condenser::Manifest.new(nil, File.join(@dir, 'manifest.json'))
    assert_raises Condenser::Error do
      manifest.compile('application.js')
    end
  end

  test "no environment raises compilation error" do
    assert !File.exist?("#{@dir}/manifest.json")

    manifest = Condenser::Manifest.new(File.join(@dir, 'manifest.json'))
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

    manifest = Condenser::Manifest.new(@env, @dir)
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

    manifest = Condenser::Manifest.new(@env, @path)
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

end