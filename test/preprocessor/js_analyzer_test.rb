require 'test_helper'

class JSAnalyzerTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.unregister_minifier('application/javascript')
  end
  
  test 'file with exports gets marked as module and exports as module' do
    @env.clear_pipeline
    @env.register_preprocessor 'application/javascript', Condenser::JSAnalyzer
    
    file 'export.js', <<~JS
      var t = { 'var': () => { return 2; } };

      export {t as name1};
    JS

    asset = assert_file 'export.js', 'application/javascript', <<~FILE
      var t = { 'var': () => { return 2; } };

      export {t as name1};
    FILE
    assert_equal "module", asset.type
        
    asset = assert_exported_file 'export.js', 'application/javascript', <<~FILE
      var t = { 'var': () => { return 2; } };

      export {t as name1};
    FILE
    assert_equal "module", asset.type
  end

  test 'file with imports gets marked as module and exports as module' do
    @env.clear_pipeline
    @env.register_preprocessor 'application/javascript', Condenser::JSAnalyzer
    
    file 'import.js', <<~JS
      import name1 from 'export'

      name1();
    JS

    asset = assert_file 'import.js', 'application/javascript', <<~FILE
      import name1 from 'export'

      name1();
    FILE
    assert_equal "module", asset.type
        
    asset = assert_exported_file 'import.js', 'application/javascript', <<~FILE
      import name1 from 'export'

      name1();
    FILE
    assert_equal "module", asset.type
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

    var resc = /[<>&\(\)\\[\\]"']/g;

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
        "module-name/path/to/specific/un-exported/file6.js",
        "module-name1.js",
        "module-name10.js",
        "module-name2.js",
        "module-name3.js",
        "module-name4.js",
        "module-name5.js",
        "module-name7.js",
        "module-name8.js",
        "module-name9.js"
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
  
  test 'another example file where / as a divisor might get confused as a regex' do
    file 'name.js', <<~JS
      row.append(`
        <td class="text-right">
          ${m(amounts_by_month[month] / 1000, 'USD', {precision: 0})}K
        </td>
      `)
    JS

    asset = @env.find('name.js')
    assert_nil asset.exports
    assert_not asset.has_default_export?
    assert_empty asset.export_dependencies
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
  
  test 'comments before imports' do
    file 'a.js', ''
    
    file 'test.js', <<-DOC
      /*
          Availabilities Index
      */
      import template from 'a';

      export default Viking.View.extend({})
    DOC

    asset = @env.find('test.js')
    assert asset.exports
    assert asset.has_default_export?
    assert_equal ['a.js'], asset.export_dependencies.map(&:filename)

    file 'test.js', <<-DOC
      // Availabilities Index
      //
      import template from 'a';

      export default Viking.View.extend({})
    DOC

    asset = @env.find('test.js')
    assert asset.exports
    assert asset.has_default_export?
    assert_equal ['a.js'], asset.export_dependencies.map(&:filename)
  end
  
  test 'imports interweaved' do
    file 'a.js', ''
    file 'b.js', ''
    
    file 'test.js', <<-DOC
      import a from 'a';
      console.log();
      import b from 'b';
    DOC

    asset = @env.find('test.js')
    assert_not asset.exports
    assert_not asset.has_default_export?
    assert_equal ['a.js', 'b.js'], asset.export_dependencies.map(&:filename)
  end
  
  test "dependency tracking for a export from" do
    file 'c.js', <<~JS
    function c() { return 'ok'; }
    
    export {c}
    JS
    
    file 'b.js', <<~JS
    export {c} from 'c';
    
    JS
    
    file 'a.js', <<~JS
    import {c} from 'b'
    
    console.log(c());
    JS

    asset = assert_file 'a.js', 'application/javascript'
    assert_equal ['/a.js', '/b.js', '/c.js'], asset.all_export_dependencies.map { |path| path.delete_prefix(@path) }
  end
  
  test 'exporting a nested object' do
    file 't.js', <<~JS
      export default {
          registry: {
              boolean: true,
              integer: 1
          }
      };
    JS
  end

  test 'regex chars that dont need escaping' do
    file 'a.js', 'this._agsAdmin=/(https?:\/\/[^/]+\/[^/]+)\/admin\/?(\/.*)?$/i'
    asset = assert_file 'a.js', 'application/javascript'

    file 'b.js', 'function T(e){return e.replaceAll(/[|\\{}()[\]^$+*?.]/g,"\\$&")}'
    asset = assert_file 'b.js', 'application/javascript'

    file 'c.js', 'f=/(?:LENGTH)?UNIT\[([^\]]+)]]$/i'
    asset = assert_file 'c.js', 'application/javascript'

    file 'd.js', 'function o(t,e){return t.replaceAll(/([.$?*|{}()[\]\\\\/+\-^])/g,(t=>e?.includes(t)?t:`\\${t}`))}'
    asset = assert_file 'd.js', 'application/javascript'
  end

  test 'a regex after a function call or for loop' do
    file 't.js', <<~JS
      for(const s in r)/^(request|service)$/i.test(s)&&delete r[s];
    JS

    asset = assert_file 't.js', 'application/javascript'
    file 'b.js', <<~JS
      e=>Math.round(1e4*e)/1e4;
    JS

    asset = assert_file 'b.js', 'application/javascript'
    file 'c.js', <<~JS
      {const e=this._timings.entries,t=e.length;let s=0;for(const r of e)s+=r;r=s/t}
    JS

    asset = assert_file 'c.js', 'application/javascript'
  end

  test 'file with a single line comment in a argument list before a regex' do
    file 'name.js', <<~JS
      function javascript(hljs) {

        regex.either(
          // Float32Array, OutT
          /\b[A-Z][a-z]+([A-Z][a-z]*|\d)*/,
          // CSSFactory, CSSFactoryT
        )

        const USE_STRICT = {
          label: "use_strict",
          className: 'meta',
          relevance: 10,
          begin: /^\s*['"]use (strict|asm)['"]/
        };

      }

      module.exports = javascript;
    JS

    asset = assert_file 'name.js', 'application/javascript'
    
    
    file 'name.js', <<~JS
      class ScrollDirective {
          constructor (scrollElement, ...args) {
              this._promise = new Promise((resolve, reject) => {
                  function step (now) {

                      const elapsed = now - this.start
                      // Behavior is (EaseOutCubic)[https://gizma.com/easing/#easeOutCubic]
                      // TODO add easing options
                      const percent = Math.min(1 - Math.pow(1 - elapsed / this.duration, 3), 1.0)
                      scrollElement.scrollTo(this.deltaX * percent + this.startX, this.deltaY * percent + this.startY)
                    
                      id = window.requestAnimationFrame(step.bind(this))
                  }

              })
          }
    
          setDirective (targetX, targetY, options={}) {
              // support (targetX, options)
              if (typeof targetY == "object") {
                  options = targetY
                  targetY = undefined
              }
              // support (options)
              if (typeof targetX == "object") {
                  options = targetX
                  targetX = undefined
              }
              if (!options.duration) {
                  this.duration = Math.max(Math.abs(this.deltaY) / this.speed, Math.abs(this.deltaX) / this.speed)
                  if (options.minDuration) {
                      this.duration = Math.max(this.duration, options.minDuration)
                  }
              }
              return this
          }

      }
    JS

    asset = assert_file 'name.js', 'application/javascript'
  end

  test 'file with a keyword as start of a function name' do
    file 'name.js', <<~JS
      export default class Admin extends User {

          static aroundActions = ['requireAdmin']
    
          async imports () {
              this.display(imports, {
                  user: this.application.session.user
              }, { layout })
          }
      }
    JS

    asset = @env.find('name.js')
    assert asset.exports
    assert asset.has_default_export?
    assert_empty asset.export_dependencies
  end

  test 'identifiers containing import are not treated as imports' do
    file 'name.js', <<~JS
      function bulk_import(locals) { return locals; }
      function import_into(locals) { return locals; }
      var reimport = 1, _import = 2, import$ = 3, importé = 4;
      bulk_import('a');
      import_into("b");
      myimport.call();
      obj.import('c');
      obj?.import('d');
      $import('e');
      ünimport('f');
      reimport = importé + import$;
    JS

    asset = @env.find('name.js')
    assert_nil asset.type
    assert_nil asset.exports
    assert_empty asset.export_dependencies
    assert_empty asset.linked_assets
  end

  test 'identifiers containing export are not treated as exports' do
    file 'name.js', <<~JS
      var exported = 1, exporter = 2, _export = 3, $export = 4, export_ = 5, ünexport = 6;
      obj.export = function () { return exported; };
      obj?.export();
      module.exports = { exporter, _export, $export };
    JS

    asset = @env.find('name.js')
    assert_nil asset.type
    assert_nil asset.exports
    assert_not asset.has_default_export?
    assert_empty asset.export_dependencies
  end

  test 'import and export as property names are not keywords' do
    file 'name.js', <<~JS
      class Loader {
        #import() { return 1; }
        #export = 2;
        run() { return this.#import() + this.#export; }
      }
      var o = { import: 1, export: 2 };
      const { import: imp, export: exp } = o;
      o. import(1);
      o
        . export(2);
      console.log(imp, exp, new Loader().run());
    JS

    asset = @env.find('name.js')
    assert_nil asset.type
    assert_nil asset.exports
    assert_empty asset.export_dependencies
    assert_empty asset.linked_assets
  end

  test 'spread with a space before import is still a dynamic import' do
    file 'a.js', ''
    file 'name.js', <<~JS
      const parts = [... import('./a')];
    JS

    asset = @env.find('name.js')
    assert_equal ['a.js'], asset.linked_assets.map(&:filename)
  end

  test 'template functions with import in their names alongside real imports and exports' do
    file 'a.js', ''
    file 'name.js', <<~JS
      import a from 'a';

      function bulk_import(locals) {
        return locals.rows.map(r => r / 2);
      }

      function importTpl_into(locals) { return bulk_import(locals); }

      export default { bulk_import, import_into: importTpl_into };
    JS

    asset = @env.find('name.js')
    assert_equal "module", asset.type
    assert asset.exports
    assert asset.has_default_export?
    assert_equal ['a.js'], asset.export_dependencies.map(&:filename)
  end

  test 'import and export keywords after other tokens' do
    %w(a b c d e f g h).each { |n| file "#{n}.js", '' }
    file 'name.js', <<~JS
      import a from 'a';import b from 'b'
      {}
      import c from 'c'
      /* c */import d from 'd'
      // c
      import e from 'e'
      function x() { return import('./f'); }import g from 'g'
      [...import('./h')];
      export {a};export const z = 1
    JS

    asset = @env.find('name.js')
    assert_equal "module", asset.type
    assert asset.exports
    assert_not asset.has_default_export?
    assert_equal %w(a.js b.js c.js d.js e.js f.js g.js h.js), asset.export_dependencies.map(&:filename).sort
    assert_equal %w(f.js h.js), asset.linked_assets.map(&:filename).sort

    file 'name.js', "export default function () {}"
    asset = @env.find('name.js')
    assert asset.has_default_export?

    file 'name.js', "x();export * from 'a'"
    asset = @env.find('name.js')
    assert asset.exports
    assert_equal ['a.js'], asset.export_dependencies.map(&:filename)
  end

  test 'import.meta is not an import' do
    file 'name.js', <<~JS
      const url = new URL('a.png', import.meta.url);
      f(import.meta.url, import . meta);
    JS

    asset = @env.find('name.js')
    assert_equal "module", asset.type
    assert_nil asset.exports
    assert_empty asset.export_dependencies
    assert_empty asset.linked_assets
  end

  test 'import and export inside strings, templates, regexes and comments' do
    file 'name.js', <<~JS
      var s = 'import a from "a"', d = "export default 1";
      var t = `import('b') ${bulk_import('c')} export * from 'd'`;
      var r = /import\\('e'\\)/, q = /export/g;
      // import f from 'f'
      /* export default g */
    JS

    asset = @env.find('name.js')
    assert_nil asset.type
    assert_nil asset.exports
    assert_empty asset.export_dependencies
    assert_empty asset.linked_assets
  end

  test 'class and object methods named import and export' do
    file 'name.js', <<~JS
      class Loader {
        import(path) { return path; }
        static export(path, options = {}) { return [path, options]; }
        async import2() { return this.import('a'); }
      }
      const o = {
        import(x) { return x; },
        export (y) { return y; },
        get import() { return 1; }
      };
    JS

    asset = @env.find('name.js')
    assert_nil asset.type
    assert_nil asset.exports
    assert_empty asset.export_dependencies
    assert_empty asset.linked_assets
  end

  test 'regex vs division' do
    file 'a.js', ''
    file 'name.js', <<~JS
      var a = 10, b = 2, c = 1, s = 'x';
      var d = a / b / c;
      var x = /re"/g, y = (a + b)/2, z = [a][0]/2, w = a++ / 2;
      function f(s) { return /it's/.test(s); }
      if (typeof /"/ === 'object') /'/.test(s);
      var g = a /* c */ / b, h = x.source.length / 2 / c;
      export default import('./a');
    JS

    asset = @env.find('name.js')
    assert_equal "module", asset.type
    assert asset.has_default_export?
    assert_equal ['a.js'], asset.linked_assets.map(&:filename)
  end

  test 'a dynamic import of a variable followed by a string containing quotes' do
    file 'name.js', <<~JS
      let shared, worker;
      if (typeof self !== "undefined") self.__mapboxImport = (u) => import(
        /* webpackIgnore: true */
        u
      );
      const workerBundleString = "self.onerror = function() { console.error('An error'); }; self.__mapboxImport = (u) => import(u); (" + shared + ")(undefined, sharedChunk); (" + worker + ")(undefined, sharedChunk);";
    JS

    asset = @env.find('name.js')
    assert_equal "module", asset.type
    assert_empty asset.linked_assets
    assert_empty asset.export_dependencies
  end

  test 'nested template literals' do
    file 'a.js', ''
    file 'b.js', ''
    file 'name.js', <<~JS
      const t = `a ${ `b ${ c ? `{` : '}' } import('x')` } ${ { d: 1 }.d / 2 } export`;
      const u = `${import('./a')}`;
      export const v = `${ `${ `\\`` }` }`, w = import(`./b`);
    JS

    asset = @env.find('name.js')
    assert_equal "module", asset.type
    assert asset.exports
    assert_not asset.has_default_export?
    assert_equal %w(a.js b.js), asset.linked_assets.map(&:filename).sort
  end

  test 'export from after other exports' do
    %w(a b c).each { |n| file "#{n}.js", '' }
    file 'name.js', <<~JS
      // Re-export the helpers.
      export { a } from './a';
      export * as b from './b';
      export {default as c} from './c';
      export default function () {}
    JS

    asset = @env.find('name.js')
    assert_equal "module", asset.type
    assert asset.has_default_export?
    assert_equal %w(a.js b.js c.js), asset.export_dependencies.map(&:filename).sort
  end

  test 'syntax errors' do
    file 'name.js', <<~JS
      var a = 1;
      var s = "unterminated
    JS

    error = assert_raises(Condenser::SyntaxError) { @env.find('name.js').process }
    assert_match(/Unexpected token \\n .*name\.js\s+2:/, error.message)

    file 'name.js', "function a() { return 1; }}"
    error = assert_raises(Condenser::SyntaxError) { @env.find('name.js').process }
    assert_match(/Unexpected token \} .*name\.js\s+1:26/, error.message)

    file 'name.js', "function a() { return `${1}"
    assert_raises(Condenser::SyntaxError) { @env.find('name.js').process }
  end

end