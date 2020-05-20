require 'test_helper'

class JSAnalyzerTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.unregister_preprocessor 'application/javascript', Condenser::BabelProcessor
    @env.register_preprocessor 'application/javascript', Condenser::JSAnalyzer
    @env.unregister_minifier('application/javascript')
  end
  
  test 'file with a single export' do
    file 'name.js', <<~JS
    var t = { 'var': () => { return 2; } };

    export {t as name1};
    JS

    asset = @env.find('name.js')
    assert asset.exports
    assert_not asset.has_default_export?
    assert_empty asset.export_dependencies
  end

  test 'more complicated file with a single export' do
    file 'name.js', <<~JS
    export function escape(string) {
        if (string !== undefined && string != null) {
            return String(string).replace(/[&<>'"\\/]/g, function (c) {
                return '&#' + c.codePointAt(0) + ';';
            });
        } else {
            return '';
        }
    }

    /*
        Adapted from https://github.com/thysultan/md.js
        modified to include urlRegExp
    */

    var unicodes = {
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;',
      '&': '&amp;',
      '[': '&#91;',
      ']': '&#93;',
      '(': '&#40;',
      ')': '&#41;',
    };

    var resc = /[<>&\(\)\[\]"']/g;

    JS

    asset = @env.find('name.js')
    assert asset.exports
    assert_not asset.has_default_export?
    assert_empty asset.export_dependencies
  end

  test 'file with a default export' do
    file 'name.js', <<~JS
    var t = { 'var': () => { return 2; } };

    export default {t as name1};
    JS

    asset = @env.find('name.js')
    assert asset.exports
    assert asset.has_default_export?
    assert_empty asset.export_dependencies
  end

  test 'file with imports' do
    1.upto(10) do |i|
      if i == 6
        file "module-name/path/to/specific/un-exported/file#{i}.js", "#{i}"
      else
        file "module-name#{i}.js", "#{i}"
      end
    end

    file 'name.js', <<~JS
      import defaultExport from "module-name1";
      import * as name from "module-name2";
      import { export1 } from "module-name3";
      import { export1 as alias1 } from "module-name4";
      import { export1 , export2 } from "module-name5";
      import { foo , bar } from "module-name/path/to/specific/un-exported/file6";
      import { export1 , export2 as alias2 , [...] } from "module-name7";
      import defaultExport, { export1 [ , [...] ] } from "module-name8";
      import defaultExport, * as name from "module-name9";
      import "module-name10";
    JS

    asset = @env.find('name.js')
    assert_nil asset.exports
    assert_equal [
        "module-name1.js",
        "module-name2.js",
        "module-name3.js",
        "module-name4.js",
        "module-name5.js",
        "module-name/path/to/specific/un-exported/file6.js",
        "module-name7.js",
        "module-name8.js",
        "module-name9.js",
        "module-name10.js"
      ], asset.export_dependencies.map(&:filename)
  end

  test 'file with import and no default export' do
    file 'a.js', ''
    file 'test.js', <<-DOC
      import LiveField from 'a'

      export function colorSpectrum(value, range, saturation, lightness) {
        range = range || 360;
        saturation = saturation || 71;
        lightness = lightness || 44;
        let hue = (value * range).toString(10);
        return `hsl(${hue}, ${saturation}%, ${lightness}%)`;
      }
    DOC

    asset = @env.find('test.js')
    assert_not_nil asset.exports
    assert_not asset.has_default_export?
    assert_equal [ "a.js" ], asset.export_dependencies.map(&:filename)
  end
  
  test 'example file where / as a divisor might get confused as a regex' do
    file 'test.js', <<-DOC
      export default function (locals) {
        for (var x = 0; x < locals.rows; x++) {
          for (var i = 0; i < locals.columns; i++) {
            __append("\\n        <td class=\\"opacity-");
            __append((locals.rows - x) / locals.rows * 100);
            __append("-p ");

            __append(locals._.sample(['', '-delay', '-delay-more']));

            __append(" rounded\\">\\n                &nbsp;\\n            </div>\\n        </td>\\n    ");
          }

          __append("\\n    </tr>\\n");
        }

        return __output.join("");
      }
    DOC
    
    asset = @env.find('test.js')
    assert asset.exports
    assert asset.has_default_export?
    assert_empty asset.export_dependencies.map(&:filename)
  end
  
  test 'x' do
    file 'test.js', <<-DOC
      this.$('.pagination').html(`
        <div class="text-center pad-v ">
            <div class="text-gray-dark margin-bottom-half">
                ${this.collection.length} ${this.collection.model.modelName.plural.titleize()}
                Loaded of
                <span class="js-total">...</span>
            </div>
            <div class="js-more-action relative">
                <button type="button" class="js-more uniformButton">Load More</button>
                <span class="margin-left">
                    Load By
                </span>
                <select class="js-per-page">
                    ${_.map([25, 50, 100], v => `<option ${this.collection.cursor.get('per_page') == v ? 'selected' : ''}>${v}</option>`).join()}
                </select>
            </div>
        </div>
      `);
    DOC
    
    asset = @env.find('test.js')
    assert_not asset.exports
    assert_not asset.has_default_export?
    assert_empty asset.export_dependencies.map(&:filename)
  end
  
end