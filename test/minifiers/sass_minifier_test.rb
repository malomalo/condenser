require 'test_helper'
require 'sass-embedded'

class SassMinifierTest < ActiveSupport::TestCase

  test 'simple example' do
    file 'test.css', <<~JS
      * {
        background: #FFFFFF;
      }
    JS

    assert_exported_file 'test.css', 'text/css', <<~CSS
      *{background:#fff}
    CSS
  end

  test 'minifies compiled scss' do
    file 'test.scss', <<~SCSS
      /* a comment */
      $color: rgba(255, 0, 0, 1);
      @media (min-width: 100px) {
        .a, .b {
          color: $color;
          margin: 0px 0 0 0;
          &:hover { color: blue; }
        }
      }
      .c { --custom: { a: b }; width: calc(100% - 10px); }
    SCSS

    assert_exported_file 'test.css', 'text/css', <<~CSS
      @media(min-width: 100px){.a,.b{color:rgb(255, 0, 0);margin:0px 0 0 0}.a:hover,.b:hover{color:blue}}.c{--custom: { a: b };width:calc(100% - 10px)}
    CSS
  end

  test 'plain css is not interpreted as Sass' do
    file 'test.css', <<~CSS
      .a { width: 10px/2; }
    CSS

    assert_exported_file 'test.css', 'text/css', <<~CSS
      .a{width:10px/2}
    CSS
  end

  test 'an error shows the file and line' do
    file 'test.css', ".a { color: red; }\n.b { color: red\n"

    error = assert_raises(Sass::CompileError) { @env.find('test.css').export }
    assert_match(/\Atest.css:2:16: expected end of rule\./, error.message)
    assert_match "2 │ .b { color: red", error.message
  end

  test 'with options' do
    @env.register_minifier 'text/css', Condenser::SassMinifier.new(style: :expanded)
    file 'test.css', ".a { color: red }"

    assert_exported_file 'test.css', 'text/css', <<~CSS
      .a {
        color: red;
      }
    CSS
  end

end
