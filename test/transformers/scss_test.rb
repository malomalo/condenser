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
      background-color: green; }
      body:hover {
        background-color: blue; }
    CSS
  end

  test 'scss import globing' do
    file "c/dir/a.scss", "body { color: blue; }"
    file "c/dir/b.scss", "body { color: green; }"

    file 'c/test.scss', '@import "./dir/*"'

    assert_file 'c/test.css', 'text/css', <<~CSS
    body {
      color: blue; }

    body {
      color: green; }
    CSS

    file 'c/test2.scss', '@import "c/dir/*"'

    assert_file 'c/test2.css', 'text/css', <<~CSS
    body {
      color: blue; }

    body {
      color: green; }
    CSS
  end

  test "url functions" do
    file 'test.scss', <<~SCSS
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
    div {
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.svg);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.png);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.mov);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.mp3);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.woff2);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.woff);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.js);
      url: url(/assets/foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.css); }
    CSS
    
    asset = @env.find('test.css')
    assert_equal ["foo.svg", "foo.png", "foo.mov", "foo.mp3", "foo.woff2", "foo.woff", "foo.js", "foo.css"], asset.process_dependencies.map(&:filename)
    assert_equal ["foo.svg", "foo.png", "foo.mov", "foo.mp3", "foo.woff2", "foo.woff", "foo.js", "foo.css"], asset.export_dependencies.map(&:filename)
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
    assert_equal ["a.scss", "d.scss", "b.scss"], asset.process_dependencies.map(&:filename)
    assert_equal ["a.scss", "d.scss", "b.scss"], asset.export_dependencies.map(&:filename)
  end
  
end
