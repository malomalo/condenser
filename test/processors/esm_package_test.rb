require 'test_helper'
require 'active_support/testing/constant_stubbing'

# Gems installed inside an app (e.g. `vendor/bundle` on CI) are under the
# app's package.json, and Node treats `.js` files there as ES modules if it
# has `"type": "module"`.
class EsmPackageTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::ConstantStubbing

  def setup
    super
    @app = File.realpath(Dir.mktmpdir)
    File.write(File.join(@app, 'package.json'), %({"type": "module"}\n))
    @lib = File.join(@app, 'vendor/bundle/gems/condenser/lib')
    FileUtils.mkdir_p(@lib)
    FileUtils.cp_r(File.expand_path('../../lib/condenser', __dir__), @lib)
  end

  def teardown
    super
    FileUtils.remove_entry(@app, true)
  end

  # The processor's script, in the copy of lib/ under the app.
  def vendored(processor)
    processor::SCRIPT.sub(File.expand_path('../../lib', __dir__), @lib)
  end

  test 'the Tailwind worker runs under a package.json with type module' do
    @env.register_preprocessor 'text/css', Condenser::TailwindProcessor.new(@env.npm_path)
    file 'index.html', %(<div class="flex"></div>\n)
    file 'application.css', %(@import "tailwindcss";\n)

    stub_const(Condenser::TailwindProcessor, :SCRIPT, vendored(Condenser::TailwindProcessor)) do
      assert_includes @env.find('application.css').source, '.flex'
    end
  end

  test 'the Rolldown worker runs under a package.json with type module' do
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path))
    file 'main.js', "console.log(1);\n"

    stub_const(Condenser::RolldownProcessor, :SCRIPT, vendored(Condenser::RolldownProcessor)) do
      assert_includes @env.find('main.js').export.source, 'console.log(1)'
    end
  end

end
