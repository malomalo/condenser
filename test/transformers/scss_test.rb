require 'test_helper'

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
    file "dir/index.scss", '@import "*";'

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

  test 'an import resolves next to the importing file before the load paths' do
    file 'config.scss', '$color: red;'
    file 'pdf/config.scss', '$color: green;'
    file 'pdf/index.scss', <<~SCSS
      @import 'config';
      .pdf { color: $color; }
    SCSS
    file 'share/index.scss', <<~SCSS
      @import 'config';
      .share { color: $color; }
    SCSS

    assert_file 'pdf/index.css', 'text/css', <<~CSS
    .pdf {
      color: green;
    }
    CSS
    assert_file 'share/index.css', 'text/css', <<~CSS
    .share {
      color: red;
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

  test 'creating a file next to the importing file changes what is imported' do
    file 'config.scss', '$color: red;'
    file 'pdf/index.scss', <<~SCSS
      @import 'config';
      .pdf { color: $color; }
    SCSS

    assert_exported_file 'pdf/index.css', 'text/css', <<~CSS
    .pdf{color:red}
    CSS
    assert_equal ["pdf/config", "config"], @env.find('pdf/index.css').instance_variable_get(:@process_dependencies).map(&:first)

    file 'pdf/config.scss', '$color: green;'

    env = Condenser.new(@path, logger: Logger.new('/dev/null'), cache: @env.cache, npm_path: @npm_dir, base: @path)
    assert_equal '.pdf{color:green}', env.find('pdf/index.css').export.source.rstrip
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

  test 'a missing import raises a Sass::CompileError' do
    file 'test.scss', '@import "missing";'

    error = assert_raises(Sass::CompileError) { @env.find('test.css').source }
    assert_match "Can't find stylesheet to import.", error.message
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
      url: url(/assets/foo-8e48022588e76a6c2fac08e7704ce16203d2cbf072352b511fa0731db64dbd51.css);
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

  test "sass options" do
    @env.register_transformer 'text/scss', 'text/css', Condenser::ScssTransformer.new(sass_config: { style: :compressed })
    file 'test.scss', 'div { a { color: red; } }'

    assert_file 'test.css', 'text/css', 'div a{color:red}'

    @env.register_transformer 'text/scss', 'text/css', Condenser::ScssTransformer.new(sass_config: { style: :nested, precision: 5 })
    file 'test2.scss', 'div { a { color: red; } }'

    assert_file 'test2.css', 'text/css', <<~CSS
    div a {
      color: red;
    }
    CSS
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
