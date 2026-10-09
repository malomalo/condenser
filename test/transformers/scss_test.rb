require 'test_helper'
require 'sass-embedded'

class CondenserSCSSTest < ActiveSupport::TestCase

  test 'find' do
    file 'test.scss', <<~SCSS
    body {
      background-color: green;

      &:hover {
        background-color: blue;
      }
    }
    SCSS

    assert_file 'test.css', 'text/css', <<~CSS
    body {
      background-color: green;
    }
    body:hover {
      background-color: blue;
    }
    CSS
  end

  test 'sass syntax' do
    @env.register_mime_type 'text/sass', extensions: %w(.sass)
    @env.register_transformer 'text/sass', 'text/css', Condenser::SassTransformer
    file 'a.scss', "div { color: red; }"
    file 'test.sass', <<~SASS
    @import 'a'
    body
      color: green
    SASS

    assert_file 'test.css', 'text/css', <<~CSS
    div {
      color: red;
    }

    body {
      color: green;
    }
    CSS
  end

  test 'scss import globing' do
    file "c/dir/a.scss", "body { color: blue; }"
    file "c/dir/b.scss", "body { color: green; }"

    file 'c/test.scss', '@import "./dir/*"'

    assert_file 'c/test.css', 'text/css', <<~CSS
    body {
      color: blue;
    }

    body {
      color: green;
    }
    CSS

    file 'c/test2.scss', '@import "c/dir/*"'

    assert_file 'c/test2.css', 'text/css', <<~CSS
    body {
      color: blue;
    }

    body {
      color: green;
    }
    CSS
  end

  test 'scss import recursive glob sorted by filename' do
    file "dir/b.scss", ".b { color: blue; }"
    file "dir/sub/a.scss", ".sub-a { color: red; }"
    file "dir/a.scss", ".a { color: green; }"
    file "dir/c.css", ".c { color: black; }"
    file "dir/d.svg", "<svg></svg>"

    file 'test.scss', '@import "dir/**/*";'

    assert_file 'test.css', 'text/css', <<~CSS
    .a {
      color: green;
    }

    .b {
      color: blue;
    }

    .c {
      color: black;
    }

    .sub-a {
      color: red;
    }
    CSS

    asset = @env.find('test.css')
    assert_equal ["dir/a.scss", "dir/b.scss", "dir/c.css", "dir/sub/a.scss"], asset.process_dependencies.map(&:filename)
  end

  test 'a glob does not import the file importing it' do
    file "dir/a.scss", ".a { color: green; }"
    file "dir/b.scss", ".b { color: blue; }"
    file "dir/index.scss", '@import "./*";'

    assert_file 'dir/index.css', 'text/css', <<~CSS
    .a {
      color: green;
    }

    .b {
      color: blue;
    }
    CSS
  end

  test 'relative imports from nested files' do
    file 'shared.scss', '.top { color: red; }'
    file 'pages/shared.scss', '.pages { color: green; }'
    file 'pages/admin/index.scss', <<~SCSS
      @import './users';
      @import '../shared';
      @import '../../shared';
    SCSS
    file 'pages/admin/users.scss', <<~SCSS
      @import './partials/table';
      .users { color: blue; }
    SCSS
    file 'pages/admin/partials/table.scss', <<~SCSS
      @import '../../shared';
      .table { color: black; }
    SCSS

    assert_file 'pages/admin/index.css', 'text/css', <<~CSS
    .pages {
      color: green;
    }

    .table {
      color: black;
    }

    .users {
      color: blue;
    }

    .pages {
      color: green;
    }

    .top {
      color: red;
    }
    CSS

    asset = @env.find('pages/admin/index.css')
    assert_equal ["pages/admin/partials/table.scss", "pages/admin/users.scss", "pages/shared.scss", "shared.scss"], asset.process_dependencies.map(&:filename).uniq.sort
  end

  test 'bare imports resolve from the load paths and ./ imports next to the importing file' do
    file 'utilities.scss', '.top-utilities { color: red; }'
    file 'components/card.scss', '.top-card { color: red; }'
    file 'share/v2/utilities.scss', '.share-utilities { color: green; }'
    file 'share/v2/components/unit.scss', '.share-unit { color: green; }'
    file 'share/v2/components/list/item.scss', '.share-item { color: green; }'
    file 'share/v2/index.scss', <<~SCSS
      @import 'utilities';
      @import 'components/*';
      @import './utilities';
      @import './components/**/*';
    SCSS

    assert_file 'share/v2/index.css', 'text/css', <<~CSS
    .top-utilities {
      color: red;
    }

    .top-card {
      color: red;
    }

    .share-utilities {
      color: green;
    }

    .share-item {
      color: green;
    }

    .share-unit {
      color: green;
    }
    CSS

    asset = @env.find('share/v2/index.css')
    assert_equal ["components/*", "share/v2/components/**/*", "share/v2/utilities", "utilities"], asset.instance_variable_get(:@process_dependencies).map(&:first).sort
  end

  test 'relative imports with ../ and dir/../' do
    file 'base.scss', '.base { color: red; }'
    file 'a/shared.scss', '.a-shared { color: green; }'
    file 'a/b/other.scss', '.a-b-other { color: blue; }'
    file 'other.scss', '.top-other { color: black; }'
    file 'a/b/index.scss', <<~SCSS
      @import '../shared';
      @import '../../base';
      @import './x/../other';
      @import 'b/../other';
    SCSS

    assert_file 'a/b/index.css', 'text/css', <<~CSS
    .a-shared {
      color: green;
    }

    .base {
      color: red;
    }

    .a-b-other {
      color: blue;
    }

    .top-other {
      color: black;
    }
    CSS
  end

  test 'an @import with several URLs' do
    file 'utilities.scss', '.top { color: red; }'
    file 'dir/utilities.scss', '.dir { color: green; }'
    file 'dir/more.scss', '.more { color: blue; }'
    file 'dir/index.scss', %q(@import "./utilities", 'utilities' , "./more";)

    assert_file 'dir/index.css', 'text/css', <<~CSS
    .dir {
      color: green;
    }

    .top {
      color: red;
    }

    .more {
      color: blue;
    }
    CSS
  end

  test '@use and @forward' do
    file 'theme.scss', '$color: red !default;'
    file 'dir/theme.scss', <<~SCSS
      $color: green !default;
      $size: 1px;
      @mixin box { padding: $size; }
    SCSS
    file 'dir/forwards.scss', <<~SCSS
      @forward './theme' show $color, box;
      @forward "./theme" as theme-* hide $size;
    SCSS
    file 'dir/index.scss', <<~SCSS
      @use 'theme' as top;
      @use './theme' as local with ($color: blue);
      @use "./forwards";
      .a { color: top.$color; }
      .b { color: local.$color; @include forwards.box; }
      .c { color: forwards.$theme-color; }
    SCSS

    assert_file 'dir/index.css', 'text/css', <<~CSS
    .a {
      color: red;
    }

    .b {
      color: blue;
      padding: 1px;
    }

    .c {
      color: blue;
    }
    CSS
  end

  test 'plain CSS imports and URLs in comments and strings are left alone' do
    file 'dir/a.scss', '.a { color: red; }'
    file 'dir/index.scss', <<~SCSS
      // @import './missing';
      /* @import "./missing"; */
      @import './a.css';
      @import url('./b.css');
      @import url(./c);
      @import 'https://example.com/d';
      @import './a' screen;
      .x { content: "@import './missing'"; }
      @import /* comment */ './a';
    SCSS

    assert_file 'dir/index.css', 'text/css', <<~CSS
    /* @import "./missing"; */
    @import './a.css';
    @import url("./b.css");
    @import url(./c);
    @import 'https://example.com/d';
    @import './a' screen;
    .x {
      content: "@import './missing'";
    }

    .a {
      color: red;
    }
    CSS
  end

  test 'relative imports in the indented syntax' do
    @env.register_mime_type 'text/sass', extensions: %w(.sass)
    @env.register_transformer 'text/sass', 'text/css', Condenser::SassTransformer
    file 'utilities.scss', '.top { color: red; }'
    file 'dir/utilities.scss', '.dir { color: green; }'
    file 'dir/more.sass', <<~SASS
      // @import ./missing
      @import ./utilities
      .more
        color: blue
    SASS
    file 'dir/index.sass', <<~SASS
      /* @import ./missing
         @import ./missing
      @import utilities, "./more"
    SASS

    assert_file 'dir/index.css', 'text/css', <<~CSS
    /* @import ./missing
     * @import ./missing */
    .top {
      color: red;
    }

    .dir {
      color: green;
    }

    .more {
      color: blue;
    }
    CSS
  end

  test 'imports not next to the importing file come from the first load path that has them' do
    other = File.realpath(Dir.mktmpdir)
    @env.append_path(other)
    file 'lib/mixins.scss', '.first { color: red; }'
    file 'lib/mixins.scss', '.second { color: green; }', base: other
    file 'lib/other.scss', '.other { color: green; }', base: other
    file 'components/card.scss', <<~SCSS
      @import 'lib/mixins';
      @import 'lib/other';
      .card { color: blue; }
    SCSS

    assert_file 'components/card.css', 'text/css', <<~CSS
    .first {
      color: red;
    }

    .other {
      color: green;
    }

    .card {
      color: blue;
    }
    CSS
  ensure
    FileUtils.remove_entry(other, true) if other
  end

  test 'a file next to the importing file does not change a bare import' do
    file 'config.scss', '$color: red;'
    file 'pdf/index.scss', <<~SCSS
      @import 'config';
      .pdf { color: $color; }
    SCSS

    assert_exported_file 'pdf/index.css', 'text/css', <<~CSS
    .pdf{color:red}
    CSS
    assert_equal ["config"], @env.find('pdf/index.css').instance_variable_get(:@process_dependencies).map(&:first)

    file 'pdf/config.scss', '$color: green;'

    env = Condenser.new(@path, logger: Logger.new('/dev/null'), cache: @env.cache, npm_path: @npm_dir, base: @path)
    assert_equal '.pdf{color:red}', env.find('pdf/index.css').export.source.rstrip
  end

  test 'npm package style fallback' do
    npm = File.realpath(Dir.mktmpdir)
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: npm, base: @path)
    file 'node_modules/stylish/package.json', '{"name": "stylish", "style": "dist/stylish.css"}', base: npm
    file 'node_modules/stylish/dist/stylish.css', '.stylish { color: pink; }', base: npm
    file 'test.scss', <<~SCSS
      @import 'stylish';
      body { color: green; }
    SCSS

    assert_equal <<~CSS.rstrip, env.find('test.css').source.rstrip
    .stylish {
      color: pink;
    }

    body {
      color: green;
    }
    CSS
  ensure
    FileUtils.remove_entry(npm, true) if npm
  end

  test 'changing an npm package style fallback reprocesses the importing file' do
    npm = File.realpath(Dir.mktmpdir)
    file 'node_modules/stylish/package.json', '{"name": "stylish", "style": "s.css"}', base: npm
    file 'node_modules/stylish/s.css', '.v1 { color: pink; }', base: npm
    file 'test.scss', '@import "stylish";'

    env = Condenser.new(@path, logger: Logger.new('/dev/null'), cache: @env.cache, npm_path: npm, base: @path)
    assert_equal ".v1 {\n  color: pink;\n}", env.find('test.css').source.rstrip

    file 'node_modules/stylish/s.css', '.v2 { color: pink; }', base: npm

    env = Condenser.new(@path, logger: Logger.new('/dev/null'), cache: @env.cache, npm_path: npm, base: @path)
    assert_equal ".v2 {\n  color: pink;\n}", env.find('test.css').source.rstrip
  ensure
    FileUtils.remove_entry(npm, true) if npm
  end

  test 'importing a templated .sass file from scss' do
    @env.register_mime_type 'text/sass', extensions: %w(.sass)
    @env.register_transformer 'text/sass', 'text/css', Condenser::SassTransformer
    file 'a.sass.erb', "div\n  color: <%= 'red' %>\n"
    file 'test.scss', "@import './a';"

    assert_file 'test.css', 'text/css', <<~CSS
    div {
      color: red;
    }
    CSS
  end

  test 'importing a templated .scss file from sass' do
    @env.register_mime_type 'text/sass', extensions: %w(.sass)
    @env.register_transformer 'text/sass', 'text/css', Condenser::SassTransformer
    file 'a.scss.erb', "div { color: <%= 'red' %>; }"
    file 'test.sass', "@import 'a'\n"

    assert_file 'test.css', 'text/css', <<~CSS
    div {
      color: red;
    }
    CSS
  end

  test 'a templated .sass file importing a relative file' do
    @env.register_mime_type 'text/sass', extensions: %w(.sass)
    @env.register_transformer 'text/sass', 'text/css', Condenser::SassTransformer
    file 'dir/b.scss', "div { color: red; }"
    file 'dir/a.sass.erb', "@import ./b\n"
    file 'b.scss', "div { color: blue; }"
    file 'test.scss', "@import 'dir/a';"

    assert_file 'test.css', 'text/css', <<~CSS
    div {
      color: red;
    }
    CSS
  end

  test 'a .css import is parsed as plain CSS' do
    file 'a.css', ".a { color: red; .b { color: blue; } }"
    file 'test.scss', "@import 'a';"

    assert_file 'test.css', 'text/css', <<~CSS
    .a {
      color: red;
      .b {
        color: blue;
      }
    }
    CSS
  end

  test 'a missing import raises a Sass::CompileError' do
    file 'test.scss', '@import "missing";'

    error = assert_raises(Sass::CompileError) { @env.find('test.css').source }
    assert_match "Can't find stylesheet to import.", error.message
  end

  test 'a missing relative import error shows the file, line and URL as written' do
    file 'missing.scss', "a { b: c; }\n@import './nope';\n"
    file 'm/a.scss', "@import '../x/nope';\n"

    error = assert_raises(Sass::CompileError) { @env.find('missing.css').source }
    assert_equal <<~MSG.chomp, error.message
      missing.scss:2:9: Can't find stylesheet to import.
        ╷
      2 │ @import './nope';
        │         ^^^^^^^^
        ╵
        missing.scss 2:9  root stylesheet
    MSG
    assert_instance_of Sass::CompileError, error.cause

    error = assert_raises(Sass::CompileError) { @env.find('m/a.css').source }
    assert_match "m/a.scss:1:9: Can't find stylesheet to import.", error.message
    assert_match "1 │ @import '../x/nope';", error.message
    assert_no_match(/condenser/, error.message)
  end

  test 'a syntax error in an imported file shows its file and line' do
    file 'dir/syntax.scss', "a {\n  b: c;\n  d: ;\n}\n"
    file 'test.scss', "@import './dir/syntax';\n"

    error = assert_raises(Sass::CompileError) { @env.find('test.css').source }
    assert_equal <<~MSG.chomp, error.message
      dir/syntax.scss:3:6: Expected expression.
        ╷
      3 │   d: ;
        │      ^
        ╵
        dir/syntax.scss 3:6  @import
        test.scss 1:9        root stylesheet
    MSG
  end

  test "url functions" do
    file 'a.scss', <<~SCSS
      body {
        color: green; }
    SCSS

    file 'test.scss', <<~SCSS
    @import 'a';

    div {
       url: asset-url("foo.svg");
       url: image-url("foo.png");
       url: video-url("foo.mov");
       url: audio-url("foo.mp3");
       url: font-url("foo.woff2");
       url: font-url("foo.woff");
       url: javascript-url("foo.js");
       url: stylesheet-url("foo.css");
    }
    SCSS

    file 'foo.svg', ''
    file 'foo.png', ''
    file 'foo.mov', ''
    file 'foo.mp3', ''
    file 'foo.woff2', ''
    file 'foo.woff', ''
    file 'foo.js', ''
    file 'foo.css', ''

    assert_file 'test.css', 'text/css', <<~CSS
    body {
      color: green;
    }

    div {
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.svg);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.png);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.mov);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.mp3);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.woff2);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.woff);
      url: url(/assets/foo-8a122aed70ad47f5ccffb10ce29103f61e194533cc95327906d40cdf46e88f4c.js);
      url: url(/assets/foo-8f1d065b11cb8b5d95bfa1804f1ceb81bb21726a7a1797f247bf763eb283fa38.css);
    }
    CSS

    asset = @env.find('test.css')
    assert_equal ["a.scss", "foo.svg", "foo.png", "foo.mov", "foo.mp3", "foo.woff2", "foo.woff", "foo.js", "foo.css"], asset.process_dependencies.map(&:filename)
    assert_equal ["a.scss", "foo.svg", "foo.png", "foo.mov", "foo.mp3", "foo.woff2", "foo.woff", "foo.js", "foo.css"], asset.export_dependencies.map(&:filename)
  end

  test "path functions" do
    file 'foo.svg', ''
    file 'foo.png', ''
    file 'test.scss', <<~SCSS
    div {
      a: asset-path("foo.svg");
      b: image-path("foo.png");
      c: url(asset-path("foo.svg"));
      d: asset-url("foo.svg", (type: image));
    }
    SCSS

    assert_file 'test.css', 'text/css', <<~CSS
    div {
      a: "/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.svg";
      b: "/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.png";
      c: url("/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.svg");
      d: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.svg);
    }
    CSS
    assert_equal ["foo.png", "foo.svg"], @env.find('test.css').linked_assets.map(&:filename).sort
  end

  test "custom functions" do
    functions = Module.new do
      def shout(text)
        ::Sass::Value::String.new(text.text.upcase, quoted: true)
      end
    end
    @env.register_transformer 'text/scss', 'text/css', Condenser::ScssTransformer.new(functions: functions) {
      def double(number, unit = nil)
        "#{(number.value * 2).to_i}#{unit&.text}"
      end
    }
    file 'test.scss', 'div { content: shout("hi"); width: double(2); height: double(3, px); }'

    assert_file 'test.css', 'text/css', <<~CSS
    div {
      content: "HI";
      width: 4;
      height: 6px;
    }
    CSS
  end

  test "changing a custom function changes the cache key" do
    cache = Condenser::Cache::MemoryStore.new
    file 'test.scss', 'div { content: tag(); }'

    compile = lambda do |value|
      file 'functions.rb', <<~RUBY
        Condenser::ScssTransformer.new {
          def tag
            #{value.inspect}
          end
        }
      RUBY
      transformer = eval(File.read(File.join(@path, 'functions.rb')), binding, File.join(@path, 'functions.rb'))
      env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, cache: cache)
      env.register_transformer 'text/scss', 'text/css', transformer
      env.find('test.css').source
    end

    assert_match 'content: one', compile.call('one')
    assert_match 'content: two', compile.call('two')
  end

  test "the default options only have the Dart Sass version" do
    assert_equal({ dart_sass: Sass::Embedded::VERSION }, Condenser::ScssTransformer.new.options)
    assert_equal({ dart_sass: Sass::Embedded::VERSION }, Condenser::ScssTransformer.new(functions: Module.new).options)
  end

  test "the Dart Sass version is part of the cache key" do
    file 'test.scss', 'div { color: red; }'
    before = @env.find('test.css').cache_key
    export_before = @env.export_pipeline_digest('text/css')

    Condenser::Sass.stubs(:version).returns('0.0.1')
    [Condenser::ScssTransformer, Condenser::SassMinifier].each { |c| c.instance_variable_set(:@instance, nil) }
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path)
    assert_not_equal before, env.find('test.css').cache_key
    assert_not_equal export_before, env.export_pipeline_digest('text/css')
  ensure
    [Condenser::ScssTransformer, Condenser::SassMinifier].each { |c| c.instance_variable_set(:@instance, nil) }
  end

  test "sass options" do
    @env.register_transformer 'text/scss', 'text/css', Condenser::ScssTransformer.new(sass_config: { style: :compressed })
    file 'test.scss', 'div { a { color: red; } }'

    assert_file 'test.css', 'text/css', 'div a{color:red}'

  end

  test "options sassc supported but Dart Sass doesn't raise an error" do
    file 'test.scss', 'div { a { color: red; } }'

    @env.register_transformer 'text/scss', 'text/css', Condenser::ScssTransformer.new(sass_config: { style: :nested })
    error = assert_raises(ArgumentError) { @env.find('test.css').process }
    assert_match(/style must be one of :expanded, :compressed/, error.message)

    @env.register_transformer 'text/scss', 'text/css', Condenser::ScssTransformer.new(sass_config: { precision: 5 })
    error = assert_raises(ArgumentError) { @env.find('test.css').process }
    assert_match(/precision/, error.message)
  end

  test "sass_config can't set the options condenser sets" do
    %i(syntax url importer importers functions logger load_paths).each do |key|
      error = assert_raises(ArgumentError) { Condenser::ScssTransformer.new(sass_config: { key => nil }) }
      assert_match "sass_config can't include :#{key}, ", error.message
    end

    error = assert_raises(ArgumentError) { Condenser::ScssTransformer.new(sass_config: { functions: {} }) }
    assert_equal "sass_config can't include :functions, use the `functions:` option or a block", error.message
    error = assert_raises(ArgumentError) { Condenser::ScssTransformer.new(sass_config: { 'logger' => nil }) }
    assert_equal 'sass_config can\'t include "logger", use the `logger:` option', error.message
  end

  test "deprecation warnings go to the logger at debug level" do
    log = StringIO.new
    @env.logger = Logger.new(log, level: :debug)
    file 'a.scss', '$x: 1;'
    file 'test.scss', <<~SCSS
      @import 'a';
      @warn "careful";
      div { width: (10px / 2); }
      .a { width: (10px / 3); }
      .b { width: (10px / 4); }
      .c { width: (10px / 5); }
      .d { width: (10px / 6); }
      .e { width: (10px / 7); }
      .f { width: (10px / 8); }
    SCSS

    @env.find('test.css').source
    assert_match(/DEBUG -- : Sass deprecation warning \[import\] condenser:\/test.scss:1: Sass @import rules are deprecated/, log.string)
    assert_match(/DEBUG -- : Sass deprecation warning \[slash-div\] condenser:\/test.scss:3/, log.string)
    assert_match(/WARN -- : Sass warning condenser:\/test.scss 2:1: careful/, log.string)
    assert_match(/DEBUG -- : Sass: \d+ repetitive deprecation warnings omitted/, log.string)
    assert_equal 1, log.string.scan(/WARN -- /).size

    log.truncate(0)
    @env.logger.level = :info
    file 'test.scss', '@import "a"; div { color: red; }'
    @env.find('test.css').source
    assert_no_match(/Sass/, log.string)
  end

  test "deprecation warnings can be silenced" do
    log = StringIO.new
    @env.logger = Logger.new(log, level: :debug)
    @env.register_transformer 'text/scss', 'text/css', Condenser::ScssTransformer.new(sass_config: { silence_deprecations: ['import'] })
    file 'a.scss', '$x: 1;'
    file 'test.scss', '@import "a"; div { color: red; }'

    @env.find('test.css').source
    assert_no_match(/deprecation/, log.string)
  end

  test "sass dependencies" do
    file 'd.scss', <<~SCSS
      $secondary-color: #444;
    SCSS

    file 'a.scss', <<~SCSS
      @import 'd';
      $primary-color: #333;
    SCSS

    file 'b.scss', <<~SCSS
      body {
        color: $primary-color;
      }
    SCSS

    file 'c.scss', <<~SCSS
      @import 'a';
      @import 'b';
    SCSS

    asset = @env.find('c.css')
    assert_equal ["a.scss", "b.scss", "d.scss"], asset.process_dependencies.map(&:filename)
    assert_equal ["a.scss", "b.scss", "d.scss"], asset.export_dependencies.map(&:filename)
  end

end
