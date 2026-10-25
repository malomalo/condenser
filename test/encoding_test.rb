require 'test_helper'

# Sources are read as binary. Text sent to Node or JSON.generate must be
# UTF-8: json 2.x warns about a BINARY string with non-ASCII bytes
# ("UTF-8 string passed as BINARY") and json 3 raises.
class EncodingTest < ActiveSupport::TestCase

  module BinaryJSONWarnings
    def warn(message, *args, **kwargs)
      EncodingTest.binary_json_warnings << message if message.include?('passed as BINARY')
      super
    end
  end
  Warning.singleton_class.prepend(BinaryJSONWarnings)

  def self.binary_json_warnings
    @binary_json_warnings ||= []
  end

  def setup
    super
    EncodingTest.binary_json_warnings.clear
    @deprecated = Warning[:deprecated]
    Warning[:deprecated] = true
  end

  def teardown
    Warning[:deprecated] = @deprecated
    assert_empty EncodingTest.binary_json_warnings
    super
  end

  def rolldown!
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@npm_dir))
  end

  test 'JavaScript bundled by Rolldown' do
    rolldown!
    file 'b.js', %{export default "naïve ✓";\n}
    file 'main.js', <<~JS
      import b from './b';
      const s = "café ✓";
      console.log(s, b);
    JS

    asset = @env.find('main.js').export
    assert_equal Encoding::UTF_8, asset.source.encoding
    assert_includes asset.source, 'console.log("café ✓", "naïve ✓");'
  end

  test 'JavaScript minified by Rolldown' do
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@npm_dir, minify: true))
    file 'main.js', %{console.log("café ✓");\n}

    assert_includes @env.find('main.js').export.source, 'café ✓'
  end

  test 'JavaScript through Babel and Terser' do
    @env.unregister_preprocessor('application/javascript', Condenser::JSAnalyzer)
    @env.register_preprocessor 'application/javascript', Condenser::BabelProcessor.new(@npm_dir,
      presets: [ ['@babel/preset-env', { modules: false, targets: { browsers: 'firefox > 41' } }] ]
    )
    @env.unregister_exporter('application/javascript')
    @env.register_minifier('application/javascript', Condenser::TerserMinifier)
    file 'main.js', %{const s = "café ✓";\nconsole.log(s);\n}

    assert_includes @env.find('main.js').source, 'var s = "café ✓";'
    assert_equal %{var s="café ✓";console.log(s);}, @env.find('main.js').export.source.strip
  end

  test 'JavaScript bundled by Rollup' do
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RollupProcessor)
    file 'b.js', %{export default "naïve ✓";\n}
    file 'main.js', %{import b from './b';\nconsole.log("café ✓", b);\n}

    source = @env.find('main.js').export.source
    assert_includes source, 'café ✓'
    assert_includes source, 'naïve ✓'
  end

  test 'ERB template' do
    rolldown!
    file 'main.js.erb', %{const s = "café ✓ <%= 'ü' %>";\nconsole.log(s);\n}

    asset = @env.find('main.js')
    assert_equal Encoding::UTF_8, asset.source.encoding
    assert_includes asset.source, 'const s = "café ✓ ü";'
    assert_includes asset.export.source, 'console.log("café ✓ ü");'
  end

  test 'ERB CSS template' do
    file 'main.css.erb', %{/* café ✓ */\nbody:after { content: "<%= 'ü' %>✓"; }\n}

    assert_includes @env.find('main.css').export.source, '"ü✓"'
  end

  # Templates get the source as read. One that needs UTF-8, like EJX, which
  # builds its JavaScript with JSON.generate, sets the encoding itself.
  test 'a template gets the source as read and sets the encoding it needs' do
    template = Class.new do
      def self.setup(environment)
      end

      def self.call(environment, input)
        source = input[:source].dup.force_encoding(Encoding::UTF_8)
        input[:source] = "export default #{JSON.generate(source)};\n"
      end
    end
    @env.register_mime_type 'application/jsonish', extensions: '.jsonish'
    @env.register_template 'application/jsonish', template
    file 'tmpl.js.jsonish', %{café ✓}

    asset = @env.find('tmpl.js')
    assert_equal Encoding::UTF_8, asset.source.encoding
    assert_equal %{export default "café ✓";\n}, asset.source
  end

  test 'a template that is not valid UTF-8 is processed as before' do
    file 'latin1.txt.erb', "caf\xE9 <%= 1 + 1 %>\n".b

    asset = @env.find('latin1.txt')
    assert_equal "caf\xE9 2\n".b, asset.source.b
  end

  test 'a byte order mark is removed from a JavaScript source' do
    file 'bom.js', "﻿console.log(\"café\");\n"

    asset = @env.find('bom.js')
    assert_equal Encoding::UTF_8, asset.source.encoding
    assert asset.source.start_with?('console.log'), asset.source.inspect
  end

  test 'an SVG that is not valid UTF-8 raises an EncodingError' do
    file 'icon.svg', %{<svg xmlns="http://www.w3.org/2000/svg"><title>caf\xE9</title></svg>\n}.b

    error = assert_raises(Condenser::EncodingError) { @env.find('icon.svg', accept: 'application/javascript').source }
    assert_equal "#{File.join(@path, 'icon.svg')} isn't valid UTF-8", error.message

    file 'icons/logo.svg', %{<svg xmlns="http://www.w3.org/2000/svg"><title>caf\xE9</title></svg>\n}.b
    error = assert_raises(Condenser::EncodingError) { @env.find('icons/logo.js').source }
    assert_equal "#{File.join(@path, 'icons/logo.svg')} isn't valid UTF-8", error.message
  end

  test 'EJS template' do
    rolldown!
    file 'tmpl.jst.ejs', %{<p>café ✓ <%= name %></p>\n}
    file 'main.js', %{import tmpl from './tmpl';\nconsole.log(tmpl({name: "ü"}));\n}

    assert_includes @env.find('tmpl.js').source, 'café ✓'
    assert_includes @env.find('main.js').export.source, 'café ✓'
  end

  test 'SVG transformed to JavaScript' do
    rolldown!
    file 'icon.svg', %{<svg xmlns="http://www.w3.org/2000/svg" aria-label="café ✓"><title>naïve</title></svg>\n}
    file 'main.js', %{import icon from './icon.svg';\nconsole.log(icon());\n}

    assert_includes @env.find('icon.svg', accept: 'application/javascript').source, '__a.setAttribute("aria-label", "café ✓");'
    assert_includes @env.find('main.js').export.source, '"café ✓"'
  end

  test 'CSS and SCSS with non-ASCII comments and content' do
    file 'a.css', %{/* café ✓ */\n.a:after { content: "✓"; }\n}
    file 'b.scss', %{// café ✓\n.b { &:after { content: "✓"; } }\n}

    assert_includes @env.find('a.css').export.source, '✓'
    assert_includes @env.find('b.css').export.source, '✓'
  end

  test 'CSS through PurgeCSS' do
    @env.register_postprocessor('text/css', Condenser::PurgeCSSProcessor)
    @env.unregister_minifier('text/css')
    file 'main.css', %{/* café ✓ */\n.used:after { content: "✓"; }\n.unused { color: red; }\n}
    file 'index.html', %{<div class="used">café ✓</div>\n}

    source = @env.find('main.css').export.source
    assert_includes source, '.used:after'
    assert_includes source, '"✓"'
    assert_not_includes source, '.unused'
  end

  test 'CSS through Tailwind' do
    @env.register_preprocessor 'text/css', Condenser::TailwindProcessor.new(@env.npm_path, base: @path)
    file 'views/index.html', %{<div class="flex">café ✓</div>\n}
    file 'application.css', %{@import "tailwindcss";\n/* café ✓ */\n.x:after { content: "✓"; }\n}

    source = @env.find('application.css').source
    assert_includes source, '.flex'
    assert_includes source, '"✓"'
  end

  test 'manifest and FileStore cache' do
    rolldown!
    @env.cache = Condenser::Cache::FileStore.new(File.join(@path, 'cache'))
    file 'main.js', %{console.log("café ✓");\n}
    file 'main.css', %{/* café ✓ */\nbody:after { content: "✓"; }\n}

    dir = File.join(@path, 'public')
    manifest = Condenser::Manifest.new(@env, dir)
    manifest.compile('main.js', 'main.css')
    assert_includes File.read(File.join(dir, manifest['main.js'][:path])), 'café ✓'

    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, cache: Condenser::Cache::FileStore.new(File.join(@path, 'cache')))
    env.unregister_exporter('application/javascript')
    env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@npm_dir))
    assert_includes env.find('main.js').export.source, 'café ✓'
  end

end
