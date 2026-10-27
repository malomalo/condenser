require 'test_helper'
require 'open3'
require 'rbconfig'

# The test helper loads ActiveSupport, so this builds in a new process that
# doesn't to catch a missing require or a core extension in lib/.
class WithoutActiveSupportTest < ActiveSupport::TestCase

  SCRIPT = <<~'RUBY'
    require 'condenser'
    require 'condenser/server'

    dir, npm_path, cache = ARGV
    env = Condenser.new(dir, listen: false, npm_path: npm_path, logger: Logger.new(File::NULL), cache: Condenser::Cache::FileStore.new(cache))
    env.register_postprocessor 'text/css', Condenser::CSSMediaCombinerProcessor.new
    manifest = Condenser::Manifest.new(env, File.join(dir, 'out'))
    manifest.compile(%w(main.js main.css page.html icon.svg))
    abort 'ActiveSupport was loaded' if defined?(ActiveSupport)
    puts manifest.filename
  RUBY

  test 'condenser builds without ActiveSupport' do
    file 'main.js', "import { a } from './a';\nconsole.log(a);\n"
    file 'a.js', "export const a = 'one';\n"
    file 'main.scss', "$c: red;\n@media screen { a { color: $c; } }\n@media screen { b { color: $c; } }\n"
    file 'page.html.erb', "<p><%= 1 + 1 %></p>\n"
    file 'icon.svg', %{<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0h1"/></svg>\n}

    Dir.mktmpdir do |cache|
      out, status = Open3.capture2e(RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', SCRIPT, @path, @npm_dir, cache)
      assert status.success?, out

      manifest = JSON.parse(File.read(out.lines.last.strip))
      assert_equal %w(icon.svg main.css main.js page.html), manifest.keys.sort
    end
  end

end
