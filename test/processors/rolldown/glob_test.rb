require 'test_helper'
require 'open3'

class RolldownGlobTest < ActiveSupport::TestCase

  def setup
    super
    @env.unregister_minifier('application/javascript')
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path))
  end

  def run_bundle(name)
    File.write(File.join(@path, 'bundle.mjs'), @env.find(name).export.source)
    stdout, stderr, status = Open3.capture3('node', File.join(@path, 'bundle.mjs'))
    assert status.success?, stderr
    stdout
  end

  def export_dependencies(name)
    @env.find(name).export_dependencies.map { |a| a.source_file.delete_prefix(File.join(@path, '')) }
  end

  test 'a ./ glob is relative to the importing file, not the load path' do
    file 'a/router.js', <<~JS
      import controllers from './controllers/*';

      console.log( controllers.join(' ') );
    JS
    file 'a/controllers/x.js', "export default 'a/x';\n"
    file 'controllers/x.js', "export default 'root/x';\n"

    assert_equal "a/x\n", run_bundle('a/router.js')
    assert_equal %w[a/controllers/x.js], export_dependencies('a/router.js')

    file 'a/controllers/y.js', "export default 'a/y';\n"
    assert_equal "a/x a/y\n", run_bundle('a/router.js')
    assert_equal %w[a/controllers/x.js a/controllers/y.js], export_dependencies('a/router.js')
  end

  test 'a ../ glob is relative to the importing file, not the load path' do
    file 'a/b/router.js', <<~JS
      import controllers from '../controllers/*';

      console.log( controllers.join(' ') );
    JS
    file 'a/controllers/x.js', "export default 'a/x';\n"
    file 'controllers/x.js', "export default 'root/x';\n"

    assert_equal "a/x\n", run_bundle('a/b/router.js')

    file 'a/controllers/y.js', "export default 'a/y';\n"
    assert_equal "a/x a/y\n", run_bundle('a/b/router.js')
  end

  test 'a ./**/* glob picks up a file added in a new directory' do
    file 'a/router.js', <<~JS
      import controllers from './controllers/**/*';

      console.log( controllers.join(' ') );
    JS
    file 'a/controllers/x.js', "export default 'a/x';\n"
    file 'controllers/x.js', "export default 'root/x';\n"

    assert_equal "a/x\n", run_bundle('a/router.js')

    file 'a/controllers/sub/y.js', "export default 'a/sub/y';\n"
    assert_equal "a/sub/y a/x\n", run_bundle('a/router.js')
  end

  test 'files with the same relative glob in different directories get their own modules' do
    file 'main.js', <<~JS
      import a from './a/router.js';
      import b from './b/router.js';

      console.log( a.concat(b).join(' ') );
    JS
    %w[a b].each do |dir|
      file "#{dir}/router.js", "import controllers from './controllers/*';\nexport default controllers;\n"
      file "#{dir}/controllers/x.js", "export default '#{dir}/x';\n"
    end

    assert_equal "a/x b/x\n", run_bundle('main.js')
  end

end
