require 'test_helper'
require 'open3'

class RolldownNpmTest < ActiveSupport::TestCase

  def setup
    super
    @packages = []
    @env.unregister_minifier('application/javascript')
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path))
  end

  def teardown
    @packages.each { |package| FileUtils.rm_rf(package) }
    super
  end

  def package(name, files)
    dir = File.join(@npm_dir, 'node_modules', name)
    @packages << dir
    files.each do |path, source|
      FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
      File.write(File.join(dir, path), source.is_a?(Hash) ? JSON.generate(source) : source)
    end
  end

  def run_bundle(name)
    source = @env.find(name).export.source
    File.write(File.join(@path, 'bundle.mjs'), source)
    stdout, stderr, status = Open3.capture3('node', File.join(@path, 'bundle.mjs'))
    assert status.success?, stderr
    [source, stdout]
  end

  test 'an exports map is resolved with the import condition' do
    package 'condenser-rolldown-exports-test', {
      'package.json' => {
        name: 'condenser-rolldown-exports-test',
        main: './main.cjs',
        exports: {
          '.' => { import: './esm.mjs', require: './cjs.cjs' },
          './feature' => { import: './feature.mjs' }
        }
      },
      'esm.mjs' => "export default 'esm';\n",
      'cjs.cjs' => "module.exports = 'cjs';\n",
      'main.cjs' => "module.exports = 'main';\n",
      'feature.mjs' => "export default 'feature';\n"
    }
    file 'main.js', <<~JS
      import value from 'condenser-rolldown-exports-test';
      import feature from 'condenser-rolldown-exports-test/feature';

      console.log( value, feature );
    JS

    source, stdout = run_bundle('main.js')
    assert_equal "esm feature\n", stdout
    assert_not_includes source, 'cjs'
    assert_not_includes source, 'main.cjs'
  end

  test 'the module field is preferred over main' do
    package 'condenser-rolldown-fields-test', {
      'package.json' => { name: 'condenser-rolldown-fields-test', main: './main.js', module: './module.js' },
      'main.js' => "module.exports = 'main';\n",
      'module.js' => "export default 'module';\n"
    }
    package 'condenser-rolldown-main-test', {
      'package.json' => { name: 'condenser-rolldown-main-test', main: './lib/index.js' },
      'lib/index.js' => "export default 'main only';\n"
    }
    file 'main.js', <<~JS
      import fields from 'condenser-rolldown-fields-test';
      import main from 'condenser-rolldown-main-test';

      console.log( fields + ', ' + main );
    JS

    source, stdout = run_bundle('main.js')
    assert_equal "module, main only\n", stdout
    assert_not_includes source, "'main'"
    assert_not_includes source, '"main"'
  end

  test 'a CommonJS package with nested requires is bundled' do
    package 'condenser-rolldown-cjs-test', {
      'package.json' => { name: 'condenser-rolldown-cjs-test', main: './index.js' },
      'index.js' => <<~JS,
        const { double } = require('./lib/double');
        exports.answer = double(require('./lib/value.json').value);
      JS
      'lib/double.js' => <<~JS,
        const one = require('../one');
        module.exports = { double: (x) => x * 2 * one };
      JS
      'lib/value.json' => '{"value": 21}',
      'one.js' => "module.exports = 1;\n"
    }
    file 'main.js', <<~JS
      import cjs, { answer } from 'condenser-rolldown-cjs-test';

      console.log( answer, cjs.answer );
    JS

    source, stdout = run_bundle('main.js')
    assert_equal "42 42\n", stdout
    assert_no_match(/\brequire\(/, source)
  end

  test 'process.env.NODE_ENV is replaced with "production"' do
    package 'condenser-rolldown-env-test', {
      'package.json' => { name: 'condenser-rolldown-env-test', main: './index.js' },
      'index.js' => <<~JS
        if (process.env.NODE_ENV === 'production') {
          module.exports = 'npm production';
        } else {
          module.exports = 'npm development';
        }
      JS
    }
    file 'main.js', <<~JS
      import env from 'condenser-rolldown-env-test';

      console.log( env, process.env.NODE_ENV );
    JS

    source, stdout = run_bundle('main.js')
    assert_equal "npm production production\n", stdout
    assert_not_includes source, 'process.env'
    assert_not_includes source, 'development'
  end

end
