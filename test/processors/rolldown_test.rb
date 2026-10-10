require 'test_helper'

class RolldownTest < ActiveSupport::TestCase

  module SpawnSpy
    def spawn(*args, **kwargs)
      super.tap { |pid| Thread.current[:spawn_pids]&.push(pid) }
    end
  end
  Process.singleton_class.prepend(SpawnSpy)
  
  def setup
    super
    @env.unregister_minifier('application/javascript')
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path))
  end
  
  test 'file is exported as module' do
    file 'main.js', <<~JS
      console.log( cube( 5 ) ); // 125
    JS
    
    asset = assert_exported_file 'main.js', 'application/javascript', <<~FILE
      //#region main.js
      console.log(cube(5));
      //#endregion
    FILE
    assert_equal "module", asset.type
  end
  
  test 'import file' do
    file 'main.js', <<~JS
      import { cube } from './math.js';

      console.log( cube( 5 ) ); // 125
    JS
    file 'math.js', <<~JS
    
      // This function isn't used anywhere, so
      // Rollup excludes it from the bundle...
      export function square ( x ) {
        return x * x;
      }

      // This function gets included
      export function cube ( x ) {
        return x * x * x;
      }
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      //#region math.js
      function cube(x) {
      	return x * x * x;
      }
      //#endregion
      //#region main.js
      console.log(cube(5));
      //#endregion
    FILE
  end
  
  test 'import an erb file' do
    file 'main.js', <<~JS
      import { cube } from './math.js';

      console.log( cube( 5 ) ); // 125
    JS
    file 'math.js.erb', <<~JS
      export function cube ( x ) {
        return <%= 2 %> * x * x;
      }
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      //#region math.js.erb
      function cube(x) {
      	return 2 * x * x;
      }
      //#endregion
      //#region main.js
      console.log(cube(5));
      //#endregion
    FILE
  end

  test 'import a file with the same name as another css file' do
    file 'a/main.js', <<~JS
      import { cube } from 'math';

      console.log( cube( 5 ) ); // 125
    JS
    file 'a/math.css', <<~CSS
      * {
        background: green;
      }
    CSS
    file 'b/math.js', <<~JS
      export function cube ( x ) {
        return x * x * x;
      }
    JS

    @env.append_path File.join(@path, 'b')
    @env.append_path File.join(@path, 'a')

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      //#region b/math.js
      function cube(x) {
      	return x * x * x;
      }
      //#endregion
      //#region a/main.js
      console.log(cube(5));
      //#endregion
    FILE
  end

  test 'import glob via /*' do
    file 'main.js', <<~JS
      import 'maths/*';

      console.log( square(cube( 5 )) );
    JS
    
    file 'maths/square.js', <<~JS
      window.square = function ( x ) {
        return x * x;
      };
    JS
    
    file 'maths/cube.js', <<~JS
      window.cube = function ( x ) {
        return x * x * x;
      };
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      //#region maths/cube.js
      window.cube = function(x) {
      	return x * x * x;
      };
      //#endregion
      //#region maths/square.js
      window.square = function(x) {
      	return x * x;
      };
      //#endregion
      //#region main.js
      console.log(square(cube(5)));
      //#endregion
    FILE
  end

  test 'import glob via /* as array' do
    file 'main.js', <<~JS
      import maths from 'maths/*';

      var x = 1;
      for (var i = 0; i < maths.length; i++) {
        x = maths[i](x);
      }
      console.log(x);
    JS
    
    file 'maths/square.js', <<~JS
      export default function square ( x ) {
        return x * x;
      };
    JS
    
    file 'maths/cube.js', <<~JS
      export default function cube ( x ) {
        return x * x * x;
      };
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~'FILE'
      //#region maths/cube.js
      function cube(x) {
      	return x * x * x;
      }
      //#endregion
      //#region maths/square.js
      function square(x) {
      	return x * x;
      }
      //#endregion
      //#region \0condenser-glob:maths/*
      var __default = [cube, square];
      //#endregion
      //#region main.js
      var x = 1;
      for (var i = 0; i < __default.length; i++) x = __default[i](x);
      console.log(x);
      //#endregion
    FILE
  end

  test 'import the same file via relative require and full path' do
    file "#{@npm_path}/module/base.js", <<~JS
      export default class Base { };
    JS
    
    file "#{@npm_path}/module/base/other.js", <<~JS
      import Base from '../base';
      
      export default class Lower extends Base { };
    JS
    
    file 'main.js', <<~JS
      import Other from 'module/base/other';
      import Base from 'module/base';

      console.log( Base, Other );
    JS


    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      //#region module/base.js
      var Base = class {};
      //#endregion
      //#region module/base/other.js
      var Lower = class extends Base {};
      //#endregion
      //#region main.js
      console.log(Base, Lower);
      //#endregion
    FILE
  end

  test 'import an aliased module' do
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path, aliases: { 'maths' => File.join(@path, 'math.js') }))

    file 'main.js', <<~JS
      import { cube } from 'maths';

      console.log( cube( 5 ) );
    JS
    file 'math.js', <<~JS
      export function cube ( x ) {
        return x * x * x;
      }
    JS

    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      //#region math.js
      function cube(x) {
      	return x * x * x;
      }
      //#endregion
      //#region main.js
      console.log(cube(5));
      //#endregion
    FILE
  end

  test 'platform: sets the conditions npm packages are resolved with' do
    package = File.join(@npm_dir, 'node_modules', 'condenser-rolldown-platform-test')
    FileUtils.mkdir_p(package)
    File.write(File.join(package, 'package.json'), JSON.generate({
      name: 'condenser-rolldown-platform-test',
      exports: { browser: './browser.js', default: './neutral.js' }
    }))
    File.write(File.join(package, 'browser.js'), "export default 'browser';\n")
    File.write(File.join(package, 'neutral.js'), "export default 'neutral';\n")
    file 'neutral.js', <<~JS
      import platform from 'condenser-rolldown-platform-test';

      console.log( platform );
    JS
    file 'browser.js', <<~JS
      import platform from 'condenser-rolldown-platform-test';

      console.log( platform );
    JS

    assert_not_includes Condenser::RolldownProcessor.new(@env.npm_path).options, :platform
    assert_includes @env.find('neutral.js').export.source, 'console.log("neutral")'

    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path, platform: 'browser'))
    assert_equal 'browser', @env.exporters['application/javascript'].first.options[:platform]
    assert_includes @env.find('browser.js').export.source, 'console.log("browser")'
  ensure
    FileUtils.rm_rf(package)
  end

  test 'the installed Rolldown version is in the options' do
    version = JSON.parse(File.read(File.join(@npm_dir, 'node_modules', 'rolldown', 'package.json')))['version']
    assert_equal version, @env.exporters['application/javascript'].first.options[:rolldown]
    digest = @env.export_pipeline_digest('application/javascript')

    file 'rolldown/package.json', JSON.generate({ name: 'rolldown', version: '0.0.0' })
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(@env.npm_path, bundler_path: File.join(@path, 'rolldown')))
    assert_equal '0.0.0', @env.exporters['application/javascript'].first.options[:rolldown]
    assert_not_equal digest, @env.export_pipeline_digest('application/javascript')
  end

  test 'an error raised in ruby stops the node process' do
    file 'main.js', <<~JS
      import maths from 'maths/*';

      console.log( maths );
    JS
    file 'maths/cube.js', <<~JS
      export default function cube ( x ) {
        return x * x * x;
      };
    JS
    Condenser::Asset.any_instance.stubs(:has_default_export?).raises(RuntimeError, 'boom')

    pids = Thread.current[:spawn_pids] = []
    error = assert_raises(RuntimeError) { @env.find('main.js').export }
    assert_equal 'boom', error.message
    assert_equal 1, pids.size
    assert_raises(Errno::ESRCH) { Process.kill(0, pids.first) }
  ensure
    Thread.current[:spawn_pids] = nil
    pids&.each { |pid| Process.kill('KILL', pid) rescue nil }
  end

  test 'the channel is closed if node can not be started' do
    file 'main.js', <<~JS
      console.log( 1 );
    JS
    sockets = UNIXSocket.pair
    UNIXSocket.stubs(:pair).returns(sockets)
    Process.stubs(:spawn).raises(Errno::ENOENT)

    assert_raises(Errno::ENOENT) { @env.find('main.js').export }
    assert sockets.all?(&:closed?)
  end

  test 'an unresolved import logs a warning' do
    file 'main.js', <<~JS
      import x from 'nope';

      console.log( x );
    JS

    log = StringIO.new
    @env.logger = Logger.new(log, level: :warn)
    assert_exported_file 'main.js', 'application/javascript', <<~FILE
      import x from "nope";
      //#region main.js
      console.log(x);
      //#endregion
    FILE
    assert_includes log.string, "WARN -- : [UNRESOLVED_IMPORT] Could not resolve 'nope' in main.js"
    assert_not_includes log.string, "\e["
  end

  test 'a build error is raised without colour codes and names the file' do
    file 'main.js', <<~JS
      import a from './bad.js';

      console.log( a );
    JS
    file 'bad.js', <<~JS
      const a = 1;
      const a = 2;
      export default a;
    JS

    error = assert_raises(RuntimeError) { @env.find('main.js').export }
    assert error.message.start_with?("Error: #{@path}/bad.js:1:7: [PARSE_ERROR] Identifier `a` has already been declared\n"), error.message
    assert_not_includes error.message, "\e["
  end

  test 'output on stdout without a trailing newline does not break the build' do
    file 'main.js', <<~JS
      import { cube } from './math.js';

      console.log( cube( 5 ) );
    JS
    file 'math.js', <<~JS
      export function cube ( x ) {
        return x * x * x;
      }
    JS
    file 'noise.js', <<~JS
      process.stdout.write('noise');
    JS

    node_options = ENV['NODE_OPTIONS']
    ENV['NODE_OPTIONS'] = "--require #{File.join(@path, 'noise.js')}"
    out, _ = capture_subprocess_io do
      Timeout.timeout(10) do
        assert_exported_file 'main.js', 'application/javascript', <<~FILE
          //#region math.js
          function cube(x) {
          	return x * x * x;
          }
          //#endregion
          //#region main.js
          console.log(cube(5));
          //#endregion
        FILE
      end
    end
    assert_equal "noise", out
  ensure
    ENV['NODE_OPTIONS'] = node_options
  end

  test 'output that looks like a protocol message does not affect the build' do
    file 'main.js', <<~JS
      console.log( 1 );
    JS
    file 'noise.js', <<~JS
      const done = JSON.stringify({ method: 'done', args: ['forged'] });
      console.log(done);
      console.error(done);
      console.log(JSON.stringify({ rid: 0, method: 'load', args: ['main.js'] }));
    JS

    node_options = ENV['NODE_OPTIONS']
    ENV['NODE_OPTIONS'] = "--require #{File.join(@path, 'noise.js')}"
    out, err = capture_subprocess_io do
      Timeout.timeout(10) do
        assert_exported_file 'main.js', 'application/javascript', <<~FILE
          //#region main.js
          console.log(1);
          //#endregion
        FILE
      end
    end
    assert_equal <<~OUT, out
      {"method":"done","args":["forged"]}
      {"rid":0,"method":"load","args":["main.js"]}
    OUT
    assert_equal %({"method":"done","args":["forged"]}\n), err
  ensure
    ENV['NODE_OPTIONS'] = node_options
  end

end
