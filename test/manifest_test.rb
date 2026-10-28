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
    assert_equal asset.path,  data['application.js']['path']
    assert_equal 15,          data['application.js']['size']
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

  test "javascript types are in the manifest" do
    file 'application.js', <<-JS
      console.log(1);
    JS
    
    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))
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

  def write_output(path, age: 0)
    path = File.join(@dir, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, 'x')
    File.utime(Time.now - age, Time.now - age, path)
  end

  def write_manifest(data, filename = File.join(@dir, 'manifest.json'))
    FileUtils.mkdir_p(File.dirname(filename))
    File.write(filename, JSON.generate(data))
    Condenser::Manifest.new(@dir, filename)
  end

  def history_dir(filename = File.join(@dir, 'manifest.json'))
    File.join(File.dirname(filename), ".#{File.basename(filename, '.*')}-builds")
  end

  # Records builds as #compile would, oldest first.
  def write_builds(*builds, filename: File.join(@dir, 'manifest.json'))
    FileUtils.mkdir_p(history_dir(filename))
    builds.each_with_index do |data, i|
      File.write(File.join(history_dir(filename), "2026010100000000000000#{i}.json"), JSON.generate(data))
    end
  end

  def recorded_builds(filename = File.join(@dir, 'manifest.json'))
    Dir.exist?(history_dir(filename)) ? Dir.children(history_dir(filename)).sort : []
  end

  def output_files
    Dir.glob('**/*', File::FNM_DOTMATCH, base: @dir).reject { |f| File.basename(f) == '.' }.sort
  end

  def output_assets
    output_files.reject { |f| f == 'manifest.json' || f.start_with?('.manifest-builds') }
  end

  # The default writers also write .gz and .br versions.
  def with_compressed(*paths)
    paths.flat_map { |path| [path, "#{path}.br", "#{path}.gz"] }.sort
  end

  def compile_version(manifest, source)
    file 'application.js', source
    manifest.compile('application.js')
    @env['application.js'].path
  end

  test "compile records a build, unless it's the same as the latest one" do
    file 'application.js', "console.log(1);"
    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))

    manifest.compile('application.js')
    assert_equal 1, recorded_builds.size
    build = File.join(history_dir, recorded_builds.first)
    assert_equal JSON.parse(File.read(manifest.filename)), JSON.parse(File.read(build))

    manifest.compile('application.js')
    Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json')).compile('application.js')
    assert_equal 1, recorded_builds.size

    manifest.add('application.js')
    manifest.export('application.js')
    assert_equal 1, recorded_builds.size
  end

  test "compiles at the same time are recorded in order" do
    file 'a.js', "console.log(1);"
    file 'b.js', "console.log(2);"
    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))

    now = Time.now
    Time.stubs(:now).returns(now)
    manifest.compile('a.js')
    manifest.compile('b.js')
    manifest.compile('a.js')
    Time.unstub(:now)

    builds = recorded_builds.map { |f| JSON.parse(File.read(File.join(history_dir, f))).keys }
    assert_equal [['a.js'], ['b.js'], ['a.js']], builds
  end

  test "clean keeps the files of the last builds" do
    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))
    v1 = compile_version(manifest, "console.log(1);")
    v2 = compile_version(manifest, "console.log(2);")
    v3 = compile_version(manifest, "console.log(3);")
    assert_equal 3, [v1, v2, v3].uniq.size
    assert_equal 3, recorded_builds.size
    first_build = recorded_builds.first

    Condenser::Manifest.new(@dir).clean(keep: 2)

    assert_equal with_compressed(v2, v3), output_assets
    assert_includes output_files, 'manifest.json'
    assert_equal 2, recorded_builds.size
    assert_not_includes recorded_builds, first_build
  end

  test "clean keeps all the builds it's told to" do
    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))
    versions = (1..3).map { |i| compile_version(manifest, "console.log(#{i});") }

    Condenser::Manifest.new(@dir).clean(keep: 3)

    assert_equal with_compressed(*versions), output_assets
    assert_equal 3, recorded_builds.size
  end

  test "clean keeps the current assets and their compressed versions" do
    manifest = write_manifest({
      'application.js' => { path: 'application-abc.js' },
      'application.css' => { path: 'application-def.css', sourcemap: 'application-def.css.map' }
    })
    write_builds({}, {})
    %w(application-abc.js application-abc.js.gz application-abc.js.br
       application-def.css application-def.css.gz application-def.css.map).each do |f|
      write_output(f)
    end

    manifest.clean

    assert_equal %w(application-abc.js application-abc.js.br application-abc.js.gz
                    application-def.css application-def.css.gz application-def.css.map), output_assets
  end

  test "clean keeps current assets in nested directories" do
    manifest = write_manifest({
      'admin/application.js' => { path: 'admin/application-abc.js' },
      'admin/pages/show.js' => { path: 'admin/pages/show-def.js', sourcemap: 'admin/pages/show-def.js.map' }
    })
    write_builds({}, {})
    %w(admin/application-abc.js admin/application-abc.js.gz
       admin/pages/show-def.js admin/pages/show-def.js.br admin/pages/show-def.js.map).each do |f|
      write_output(f)
    end

    manifest.clean

    assert_equal %w(admin admin/application-abc.js admin/application-abc.js.gz
                    admin/pages admin/pages/show-def.js admin/pages/show-def.js.br
                    admin/pages/show-def.js.map), output_assets
  end

  test "clean keeps the current manifest's files added after the last compile" do
    file 'other.js', "console.log('other');"
    manifest = Condenser::Manifest.new(@env, File.join(@dir, 'manifest.json'))
    compile_version(manifest, "console.log(1);")
    v2 = compile_version(manifest, "console.log(2);")
    manifest.add('other.js')
    other = @env['other.js'].path

    manifest.clean(keep: 1)
    assert_equal with_compressed(v2, other), output_assets

    manifest.export('other.js')
    Condenser::Manifest.new(@dir).clean(keep: 1)
    assert_equal with_compressed(v2, other), output_assets
  end

  test "clean removes files that aren't in the manifest or a kept build, even new ones" do
    manifest = write_manifest({ 'application.js' => { path: 'application-abc.js' } })
    write_builds({ 'application.js' => { path: 'application-old.js' } },
                 { 'application.js' => { path: 'application-prev.js' } },
                 { 'application.js' => { path: 'application-abc.js' } })
    write_output('application-abc.js')
    write_output('application-old.js', age: 5 * 7 * 24 * 60 * 60)
    write_output('application-prev.js')
    write_output('application-prev.js.br')
    write_output('removed-new.js')
    write_output('removed-new.js.gz')

    manifest.clean

    assert_equal %w(application-abc.js application-prev.js application-prev.js.br), output_assets
    assert_equal 2, recorded_builds.size
  end

  test "clean doesn't remove anything until enough builds are recorded" do
    manifest = write_manifest({ 'application.js' => { path: 'application-abc.js' } })
    write_output('application-abc.js')
    write_output('application-old.js')

    manifest.clean
    assert_equal %w(application-abc.js application-old.js), output_assets

    write_builds({ 'application.js' => { path: 'application-abc.js' } })
    manifest.clean
    assert_equal %w(application-abc.js application-old.js), output_assets
    manifest.clean(keep: 1)
    assert_equal %w(application-abc.js), output_assets
  end

  test "clean raises for an invalid keep" do
    manifest = write_manifest({})
    [0, -1, nil, '2', 1.5].each do |keep|
      assert_raises(ArgumentError) { manifest.clean(keep: keep) }
    end
  end

  test "clean removes old files in nested directories and directories left empty" do
    manifest = write_manifest({ 'admin/application.js' => { path: 'admin/application-abc.js' } })
    write_builds({}, { 'admin/new.js' => { path: 'admin/new/a-new.js' } })
    write_output('admin/application-abc.js')
    write_output('admin/application-old.js')
    write_output('admin/old/a/b/c-old.js')
    write_output('admin/new/a-new.js')
    write_output('stale/a/b/c-old.js')
    FileUtils.mkdir_p(File.join(@dir, 'empty/a'))

    manifest.clean

    assert_equal %w(admin admin/application-abc.js admin/new admin/new/a-new.js), output_assets
  end

  test "clean doesn't remove the manifest or its history" do
    filename = File.join(@dir, '.manifests', 'manifest-123.json')
    manifest = write_manifest({ 'application.js' => { path: 'application-abc.js' } }, filename)
    write_builds({}, {}, filename: filename)
    write_output('application-abc.js')

    manifest.clean

    assert_equal %w(.manifests .manifests/.manifest-123-builds
                    .manifests/.manifest-123-builds/20260101000000000000000.json
                    .manifests/.manifest-123-builds/20260101000000000000001.json
                    .manifests/manifest-123.json application-abc.js), output_files
  end

  test "clean doesn't remove files outside the output directory" do
    outside = Dir.mktmpdir
    write_output('application-old.js')
    File.write(File.join(outside, 'other.js'), 'x')
    File.symlink(outside, File.join(@dir, 'linked'))
    filename = File.join(outside, 'manifest.json')
    manifest = write_manifest({}, filename)
    write_builds({}, {}, {}, filename: filename)

    manifest.clean

    assert_equal %w(linked), output_files
    assert File.exist?(File.join(outside, 'other.js'))
    assert File.exist?(filename)
    assert_equal 2, recorded_builds(filename).size
  ensure
    FileUtils.remove_entry(outside, true)
  end

  test "clean reads each directory once" do
    manifest = write_manifest({ 'a/b/c/current.js' => { path: 'a/b/c/current-abc.js' } })
    write_builds({}, {})
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
    assert_equal %w(a a/b a/b/c a/b/c/current-abc.js), output_assets
  ensure
    Thread.current[:dir_reads] = nil
  end

  test "clobber removes the manifest and everything in the output directory" do
    manifest = write_manifest({ 'admin/application.js' => { path: 'admin/application-abc.js' } })
    write_builds({}, {})
    write_output('admin/application-abc.js')
    write_output('application-old.js')

    manifest.clobber

    assert File.directory?(@dir)
    assert_equal [], output_files
  end

  test "clobber removes the history of a manifest outside the output directory" do
    outside = Dir.mktmpdir
    filename = File.join(outside, 'manifest.json')
    manifest = write_manifest({}, filename)
    write_builds({}, {}, filename: filename)
    write_output('application-abc.js')

    manifest.clobber

    assert_equal [], output_files
    assert_equal [], Dir.children(outside)
  ensure
    FileUtils.remove_entry(outside, true)
  end
end
