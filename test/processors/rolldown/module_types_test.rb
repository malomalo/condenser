require 'test_helper'

class RolldownModuleTypesTest < ActiveSupport::TestCase

  # The signature and IHDR chunk of a 1x1 PNG.
  PNG = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\b\x06\x00\x00\x00\x1F\x15\xC4\x89".b
  PNG_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
  TTF = "\x00\x01\x00\x00\x00\x0F\x00\x80".b
  MODULE_TYPES = { png: :dataurl, ttf: :base64, svg: :text }

  def setup
    super
    register_rolldown(@env)
  end

  def teardown
    super
    FileUtils.remove_entry(@cache_dir, true) if @cache_dir
  end

  def register_rolldown(env, **options)
    env.unregister_minifier('application/javascript')
    env.unregister_exporter('application/javascript')
    env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@npm_dir, module_types: MODULE_TYPES, **options))
  end

  def new_env
    @cache_dir ||= File.realpath(Dir.mktmpdir)
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, cache: Condenser::Cache::FileStore.new(@cache_dir))
    register_rolldown(env)
    env
  end

  # Another environment, exporting with these RolldownProcessor options.
  def env_with(**options)
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, listen: false)
    register_rolldown(env, **options)
    env
  end

  test 'a .png is imported as a data URL through the load paths' do
    file 'images/logo.png', PNG
    file 'main.js', <<~JS
      import logo from 'images/logo.png';

      console.log( logo );
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      // main.js
      console.log("data:image/png;base64,#{PNG_BASE64}");
    FILE
  end

  test 'a .ttf is imported as base64' do
    file 'fonts/Regular.ttf', TTF
    file 'main.js', <<~JS
      import font from 'fonts/Regular.ttf';

      console.log( font );
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      // main.js
      console.log("AAEAAAAPAIA=");
    FILE
  end

  # The SVGTransformer turns an .svg into JavaScript, but the module type
  # says how an .svg import is loaded, so it's not used for one.
  test 'a module type is used instead of a transformer for its extension' do
    assert @env.transformers['image/svg+xml']
    file 'images/logo.svg', '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
    file 'main.js', <<~JS
      import logo from 'images/logo.svg';
      import relative from './images/logo.svg';

      console.log( logo, relative );
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      // images/logo.svg
      var logo_default = "<svg xmlns=\\"http://www.w3.org/2000/svg\\"></svg>";
      // main.js
      console.log(logo_default, logo_default);
    FILE

    assert_includes env_with(module_types: {}).find('main.js').export.source, 'createElementNS'
  end

  test 'a file is imported relative to the importing file' do
    file 'logo.png', 'not this one'
    file 'app/logo.png', PNG
    file 'app/main.js', <<~JS
      import logo from './logo.png';
      import parent from '../app/logo.png';

      console.log( logo, parent );
    JS

    assert_exported_file 'app/main.js', 'application/javascript', <<~FILE
      // app/logo.png
      var logo_default = "data:image/png;base64,#{PNG_BASE64}";
      // app/main.js
      console.log(logo_default, logo_default);
    FILE
  end

  test 'a file is imported through an alias' do
    register_rolldown(@env, aliases: { 'images' => File.join(@path, 'vendor/images') })
    file 'vendor/images/logo.png', PNG
    file 'main.js', <<~JS
      import logo from 'images/logo.png';

      console.log( logo );
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      // main.js
      console.log("data:image/png;base64,#{PNG_BASE64}");
    FILE
  end

  test 'a file in the load paths is used before an alias' do
    register_rolldown(@env, aliases: { 'images' => File.join(@path, 'vendor/images') })
    file 'vendor/images/logo.png', 'not this one'
    file 'images/logo.png', PNG
    file 'main.js', <<~JS
      import logo from 'images/logo.png';

      console.log( logo );
    JS

    assert_includes @env.find('main.js').export.source, "data:image/png;base64,#{PNG_BASE64}"
  end

  test 'a file is imported by its absolute path' do
    file 'images/logo.png', PNG
    file 'main.js', <<~JS
      import logo from '#{File.join(@path, 'images/logo.png')}';

      console.log( logo );
    JS

    assert_includes @env.find('main.js').export.source, "data:image/png;base64,#{PNG_BASE64}"
  end

  test 'a missing file is an error naming the import' do
    file 'main.js', <<~JS
      import logo from 'images/missing.png';

      console.log( logo );
    JS

    error = assert_raises(RuntimeError) { @env.find('main.js').export }
    assert error.message.start_with?("Error: #{@path}/main.js:1:18: [UNRESOLVED_IMPORT] Could not resolve 'images/missing.png' in main.js"), error.message
  end

  test 'without module_types a .png import fails' do
    register_rolldown(@env, module_types: {})
    file 'images/logo.png', PNG
    file 'main.js', <<~JS
      import logo from 'images/logo.png';

      console.log( logo );
    JS
    file 'relative.js', <<~JS
      import logo from './images/logo.png';

      console.log( logo );
    JS

    error = assert_raises(RuntimeError) { @env.find('main.js').export }
    assert error.message.start_with?("Error: #{@path}/main.js:1:18: [UNRESOLVED_IMPORT] Could not resolve 'images/logo.png' in main.js"), error.message
    error = assert_raises(RuntimeError) { @env.find('relative.js').export }
    assert error.message.start_with?("Error: relative.js:1:18: [UNLOADABLE_DEPENDENCY] Could not load images/logo.png"), error.message
  end

  test 'a dynamic import of a file is inlined' do
    file 'images/logo.png', PNG
    file 'main.js', <<~JS
      const logo = await import('images/logo.png');

      console.log( logo.default );
    JS

    [:inline, :keep].each do |dynamic_imports|
      source = env_with(dynamic_imports: dynamic_imports).find('main.js').export.source
      assert_includes source, "data:image/png;base64,#{PNG_BASE64}", dynamic_imports
      assert_not_includes source, 'import(', dynamic_imports
    end
  end

  test 'module_types are normalized into the options' do
    processor = Condenser::RolldownProcessor.new(@npm_dir, module_types: { ttf: :base64, 'png' => 'dataurl' })
    assert_equal({ 'png' => 'dataurl', 'ttf' => 'base64' }, processor.options[:module_types])
    assert_equal processor.options, Condenser::RolldownProcessor.new(@npm_dir, module_types: { png: :dataurl, ttf: :base64 }).options
    assert_not_includes Condenser::RolldownProcessor.new(@npm_dir).options.keys, :module_types
  end

  test 'module_types change the export digest and the etag' do
    file 'main.js', "console.log( 1 );\n"
    plain = env_with(module_types: {})
    assert_not_equal plain.export_pipeline_digest('application/javascript'), @env.export_pipeline_digest('application/javascript')
    assert_not_equal plain.find('main.js').etag, @env.find('main.js').etag
  end

  test 'module_types are checked' do
    {
      { '.png' => :dataurl } => 'module_types keys must be file extensions like :png, got ".png" (without the leading dot: :png)',
      { '.png': :dataurl } => 'module_types keys must be file extensions like :png, got :".png" (without the leading dot: :png)',
      { 'images/*.png' => :dataurl } => 'module_types keys must be file extensions like :png, got "images/*.png"',
      { 1 => :dataurl } => 'module_types keys must be file extensions like :png, got 1',
      { png: :data_url } => 'module_types[:png] must be one of [:base64, :binary, :dataurl, :empty, :js, :json, :jsx, :text, :ts, :tsx], got :data_url',
      { png: :asset } => 'module_types[:png] must be one of [:base64, :binary, :dataurl, :empty, :js, :json, :jsx, :text, :ts, :tsx], got :asset',
      { png: nil } => 'module_types[:png] must be one of [:base64, :binary, :dataurl, :empty, :js, :json, :jsx, :text, :ts, :tsx], got nil',
      [[:png, :dataurl]] => 'module_types must be a Hash of extension => module type, got [[:png, :dataurl]]'
    }.each do |module_types, message|
      error = assert_raises(ArgumentError) { Condenser::RolldownProcessor.new(@npm_dir, module_types: module_types) }
      assert_equal message, error.message
    end
  end

  test 'an imported file is an export dependency' do
    file 'images/logo.png', PNG
    file 'fonts/Regular.ttf', TTF
    file 'main.js', <<~JS
      import logo from 'images/logo.png';
      import font from './fonts/Regular.ttf';

      console.log( logo, font );
    JS

    assert_equal ['fonts/Regular.ttf', 'images/logo.png'], @env.find('main.js').export_dependencies.map(&:filename).sort
  end

  test 'a replaced file rebuilds the bundle' do
    skip 'needs a listener' if !@env.build_cache.listening
    file 'images/logo.png', PNG
    file 'main.js', <<~JS
      import logo from 'images/logo.png';

      console.log( logo );
    JS

    asset = @env.find('main.js').export
    assert_includes asset.source, PNG_BASE64
    file 'images/logo.png', TTF
    assert wait_until { @env.find('main.js').export.source.include?('data:image/png;base64,AAEAAAAPAIA=') }
    assert_not_equal asset.etag, @env.find('main.js').export.etag
  end

  test 'a replaced file rebuilds the bundle in a new process' do
    file 'images/logo.png', PNG
    file 'fonts/Regular.ttf', TTF
    file 'main.js', <<~JS
      import logo from 'images/logo.png';
      import font from './fonts/Regular.ttf';

      console.log( logo, font );
    JS

    asset = new_env.find('main.js').export
    assert_includes asset.source, PNG_BASE64
    assert_equal asset.source, new_env.find('main.js').export.source

    file 'images/logo.png', TTF
    rebuilt = new_env.find('main.js').export
    assert_includes rebuilt.source, 'data:image/png;base64,AAEAAAAPAIA='
    assert_not_equal asset.etag, rebuilt.etag

    file 'fonts/Regular.ttf', PNG
    assert_includes new_env.find('main.js').export.source, %("#{PNG_BASE64}")
  end

end
