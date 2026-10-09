require 'test_helper'

class SassRelativeImportsTest < ActiveSupport::TestCase

  def rewrite(source, indented: false)
    Condenser::Sass::RelativeImports.rewrite(source, indented: indented) { |url| "R(#{url})" }
  end

  test 'relative URLs in @import, @use and @forward' do
    assert_equal <<~SCSS, rewrite(<<~SCSS)
      @use "R(./a)" as a with ($x: "./not-a-url", $y: 1);
      @forward 'R(../b)' show c, $d;
      @forward "R(./e)" as e-* hide f;
      @import "R(./g)", 'h', "R(../i)",
        "R(./j)";
      .k { @import 'R(./l)'; }
      @use 'm';
    SCSS
      @use "./a" as a with ($x: "./not-a-url", $y: 1);
      @forward '../b' show c, $d;
      @forward "./e" as e-* hide f;
      @import "./g", 'h', "../i",
        "./j";
      .k { @import './l'; }
      @use 'm';
    SCSS
  end

  test 'plain CSS imports are left alone' do
    source = <<~'SCSS'
      @import './a.css';
      @import url(./b);
      @import url("./c");
      @import "http://example.com/d", 'https://example.com/e', '//example.com/f';
      @import "./g" screen and (min-width: 100px);
      @import "./h" supports(display: grid);
      @import "./#{$i}";
    SCSS
    assert_equal source, rewrite(source)
  end

  test 'comments and strings are left alone' do
    source = <<~SCSS
      // @import './a';
      /* @import './b';
         @use "./c"; */
      .d { content: "@import './e'"; background: url(http://example.com/@import'./f'); }
      .g { content: 'it\\'s @import "./h"'; }
      $not-a-rule@import: 1;
      @importer './i';
    SCSS
    assert_equal source, rewrite(source)
  end

  test 'comments between URLs' do
    assert_equal %q(@import /* x */ "R(./a)" /* y */, 'R(./b)';), rewrite(%q(@import /* x */ "./a" /* y */, './b';))
  end

  test 'non-ASCII sources' do
    assert_equal %(.é { content: "日本"; }\n@import "R(./ü)";), rewrite(%(.é { content: "日本"; }\n@import "./ü";))
  end

  test 'indented syntax' do
    assert_equal <<~SASS, rewrite(<<~SASS, indented: true)
      // @import ./a
      /* @import ./b
         @import ./c
      @import "R(./d)", e, "R(../f)"
      @use "R(./g)" as g
      .h
        @import "R(./i)"
        content: "@import ./j"
    SASS
      // @import ./a
      /* @import ./b
         @import ./c
      @import ./d, e, ../f
      @use "./g" as g
      .h
        @import ./i
        content: "@import ./j"
    SASS
  end

end
