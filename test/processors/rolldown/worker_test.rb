require 'test_helper'

class RolldownWorkerTest < ActiveSupport::TestCase

  module AnswerSpy
    def answer(method, *args)
      RolldownWorkerTest.on_answer&.call(method, args, self)
      super
    end
  end
  Condenser::RolldownProcessor::Runner.prepend(AnswerSpy)

  module SpawnSpy
    def spawn(*args, **kwargs)
      super.tap { |pid| Thread.current[:rolldown_worker_spawns]&.push(pid) }
    end
  end
  Process.singleton_class.prepend(SpawnSpy)

  class << self
    attr_accessor :on_answer
  end

  class Abort < Exception; end

  def setup
    super
    @env.unregister_minifier('application/javascript')
    register_rolldown
    file 'main.js', <<~JS
      import { cube } from './math.js';

      console.log( cube( 5 ) );
    JS
    file 'math.js', <<~JS
      export function cube ( x ) {
        return x * x * x;
      }
    JS
  end

  def teardown
    RolldownWorkerTest.on_answer = nil
    super
  end

  def register_rolldown(processor = nil, **options)
    @processor = processor || Condenser::RolldownProcessor.new(@env.npm_path, **options)
    @env.unregister_exporter('application/javascript')
    @env.register_exporter('application/javascript', @processor)
  end

  # Exports through the processor itself, so condenser's export cache doesn't
  # skip the build.
  def export(name, processor: @processor, source: nil)
    asset = @env.find(name)
    input = { source: source || asset.source.dup, source_file: asset.source_file, filename: asset.filename.dup, content_types: asset.content_types, map: nil }
    processor.call(@env, input)[:source]
  end

  def worker_pid(processor = @processor)
    processor.worker.pid
  end

  def alive?(pid)
    Process.kill(0, pid) == 1
  rescue Errno::ESRCH
    false
  end

  def wait_until(seconds = 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    sleep 0.05 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    yield
  end

  def on_answer(&block)
    RolldownWorkerTest.on_answer = block
  end

  def loads
    loaded = []
    on_answer { |method, args, _| loaded << args[0] if method == 'load' }
    yield
    loaded
  ensure
    RolldownWorkerTest.on_answer = nil
  end

  test 'exports reuse one worker' do
    reference = export('main.js')
    assert_includes reference, 'x * x * x'
    pid = worker_pid
    assert alive?(pid)

    assert_equal reference, export('main.js')
    assert_equal pid, worker_pid
  end

  test 'a processor registered as a class reuses one instance per npm path' do
    register_rolldown(Condenser::RolldownProcessor)
    workers = []
    on_answer { |_, _, runner| workers << runner.instance_variable_get(:@worker) }
    reference = export('main.js')
    pid = workers.first.pid

    assert_equal reference, export('main.js')
    assert_equal 1, workers.uniq.size
    assert_equal pid, workers.first.pid
    assert alive?(pid)
  end

  test 'each instance has its own worker' do
    file 'main.js', <<~JS
      import value from 'condenser-alias';

      console.log( value );
    JS
    file 'aliased.js', "export default 'aliased';\n"

    plain = Condenser::RolldownProcessor.new(@env.npm_path)
    aliased = Condenser::RolldownProcessor.new(@env.npm_path, aliases: { 'condenser-alias' => File.join(@path, 'aliased.js') }, platform: 'browser')
    assert_includes export('main.js', processor: aliased), '"aliased"'
    assert_includes export('main.js', processor: plain), 'from "condenser-alias"'
    assert_includes export('main.js', processor: aliased), '"aliased"'
    assert_not_equal worker_pid(plain), worker_pid(aliased)
    assert alive?(worker_pid(plain))
    assert alive?(worker_pid(aliased))
  end

  test 'the worker options are not part of the options' do
    default = Condenser::RolldownProcessor.new(@env.npm_path)
    tuned = Condenser::RolldownProcessor.new(@env.npm_path, max_builds: 3, max_memory: 1024)
    assert_equal default.options, tuned.options
    assert_equal %i[prefix dynamic_imports aliases rolldown], default.options.keys

    digest = @env.export_pipeline_digest('application/javascript')
    register_rolldown(tuned)
    assert_equal digest, @env.export_pipeline_digest('application/javascript')
  end

  test 'a worker killed between exports is restarted' do
    reference = export('main.js')
    pid = worker_pid
    Process.kill('KILL', pid)

    assert_equal reference, export('main.js')
    assert_not_equal pid, worker_pid
    assert_not alive?(pid)
  end

  test 'a worker killed during an export is replaced and the export retried once' do
    reference = export('main.js')
    killed = []
    on_answer do |method, _, _|
      if method == 'resolve' && killed.empty?
        killed << worker_pid
        Process.kill('KILL', killed.first)
      end
    end

    assert_equal reference, export('main.js')
    assert_equal 1, killed.size
    assert_not_equal killed.first, worker_pid
    assert_not alive?(killed.first)
  end

  test 'a worker that dies on the retry too raises an error' do
    export('main.js')
    killed = []
    on_answer do |method, _, _|
      if method == 'resolve'
        killed << worker_pid
        Process.kill('KILL', killed.last)
      end
    end

    error = assert_raises(RuntimeError) { export('main.js') }
    assert_match(/\Arolldown exited with pid \d+ SIGKILL/, error.message)
    assert_equal 2, killed.size
    assert_nil worker_pid
    killed.each { |pid| assert_not alive?(pid) }
  end

  test 'a partial last line from a worker that died mid-write is not parsed' do
    file 'partial.js', <<~JS
      const net = require('net');
      const write = net.Socket.prototype.write;
      net.Socket.prototype.write = function (data, ...rest) {
        if (typeof data === 'string' && data.includes('"method":"load"')) {
          require('fs').writeSync(3, data.slice(0, 12));
          process.exit(1);
        }
        return write.call(this, data, ...rest);
      };
    JS

    node_options = ENV['NODE_OPTIONS']
    ENV['NODE_OPTIONS'] = "--require #{File.join(@path, 'partial.js')}"
    error = assert_raises(RuntimeError) { export('main.js') }
    assert_match(/\Arolldown exited with pid \d+ exit 1/, error.message)
    assert_nil worker_pid
  ensure
    ENV['NODE_OPTIONS'] = node_options
  end

  test 'stop_workers stops the worker' do
    reference = export('main.js')
    pid = worker_pid

    Condenser::RolldownProcessor.stop_workers
    assert_not alive?(pid)
    assert_nil worker_pid

    assert_equal reference, export('main.js')
    assert_not_equal pid, worker_pid
  end

  test 'a ruby exception while answering re-raises the original exception and keeps the worker' do
    file 'main.js', <<~JS
      import maths from 'maths/*';

      console.log( maths.map((f) => f(2)) );
    JS
    5.times { |i| file "maths/f#{i}.js", "export default function f#{i} (x) { return x + #{i}; }\n" }
    reference = export('main.js')
    Condenser::RolldownProcessor.stop_workers

    on_answer do |method, args, _|
      raise ArgumentError, 'boom' if method == 'load' && args[0].end_with?('f2.js')
    end
    error = assert_raises(ArgumentError) { export('main.js') }
    assert_equal 'boom', error.message
    pid = worker_pid
    assert alive?(pid)

    RolldownWorkerTest.on_answer = nil
    assert_equal reference, export('main.js')
    assert_equal pid, worker_pid
  end

  test 'a request from an earlier build is not answered by the current one' do
    file 'stale.js', <<~JS
      const net = require('net');
      const write = net.Socket.prototype.write;
      let first = null, forged = false;
      net.Socket.prototype.write = function (data, ...rest) {
        const message = typeof data === 'string' && data.startsWith('{"rid"') ? JSON.parse(data) : null;
        if (message && first === null) first = message.build;
        if (message && !forged && message.build !== first) {
          forged = true;
          write.call(this, JSON.stringify({ rid: 1e9, build: first, method: 'load', args: ['forged.js'] }) + "\\n");
        }
        return write.call(this, data, ...rest);
      };
    JS

    node_options = ENV['NODE_OPTIONS']
    ENV['NODE_OPTIONS'] = "--require #{File.join(@path, 'stale.js')}"
    reference = export('main.js')
    answered = []
    on_answer { |method, args, _| answered << args[0] }
    assert_equal reference, export('main.js')
    assert_not_includes answered, 'forged.js'
    assert_includes answered, './math.js'
  ensure
    ENV['NODE_OPTIONS'] = node_options
  end

  test 'an exception that abandons a build stops the worker' do
    reference = export('main.js')
    pid = worker_pid

    on_answer { |method, _, _| raise Abort if method == 'resolve' }
    assert_raises(Abort) { export('main.js') }
    assert_not alive?(pid)
    assert_nil worker_pid

    RolldownWorkerTest.on_answer = nil
    assert_equal reference, export('main.js')
  end

  test 'a build error is raised for that build only' do
    file 'broken.js', <<~JS
      import x from './missing.js';

      console.log( x );
    JS
    log = StringIO.new
    @env.logger = Logger.new(log, level: :warn)
    file 'warns.js', <<~JS
      import x from 'nope';

      console.log( x );
    JS

    reference = export('main.js')
    error = assert_raises(RuntimeError) { export('broken.js') }
    assert_includes error.message, '[UNRESOLVED_IMPORT]'
    assert_equal reference, export('main.js')
    assert_empty log.string

    export('warns.js')
    assert_equal 1, log.string.scan('[UNRESOLVED_IMPORT]').size
    export('main.js')
    assert_equal 1, log.string.scan('[UNRESOLVED_IMPORT]').size
  end

  test 'concurrent exports share the worker one build at a time' do
    file 'other.js', <<~JS
      import { cube } from './math.js';

      console.log( cube( 6 ) );
    JS
    references = { 'main.js' => export('main.js'), 'other.js' => export('other.js') }
    pid = worker_pid

    results = 4.times.map { |i| Thread.new { export(i.even? ? 'main.js' : 'other.js') } }.map(&:value)
    assert_equal 4.times.map { |i| references[i.even? ? 'main.js' : 'other.js'] }, results
    assert_equal pid, worker_pid
  end

  test 'an export started while answering a build uses a throwaway worker' do
    file 'other.js', <<~JS
      console.log( 'other' );
    JS
    spawned = Thread.current[:rolldown_worker_spawns] = []
    nested = nil
    on_answer do |method, args, _|
      if method == 'load' && args[0].end_with?('math.js') && nested.nil?
        nested = Timeout.timeout(30) { export('other.js') }
      end
    end

    assert_includes export('main.js'), 'x * x * x'
    assert_includes nested, 'console.log("other")'
    assert_equal 2, spawned.size
    assert_equal spawned.first, worker_pid
    assert alive?(worker_pid)
    assert_not alive?(spawned.last)
  ensure
    Thread.current[:rolldown_worker_spawns] = nil
  end

  test 'max_builds: restarts the worker after that many builds' do
    register_rolldown(max_builds: 2)
    reference = export('main.js')
    first = worker_pid

    assert_equal reference, export('main.js')
    assert_nil worker_pid
    assert_not alive?(first)

    assert_equal reference, export('main.js')
    assert alive?(worker_pid)
    assert_not_equal first, worker_pid
  end

  test 'max_builds: and max_memory: only accept positive integers' do
    [nil, 0, -1, 1.5, '5'].each do |value|
      %i[max_builds max_memory].each do |option|
        error = assert_raises(ArgumentError) { Condenser::RolldownProcessor.new(@env.npm_path, option => value) }
        assert_equal "#{option} must be a positive Integer, got #{value.inspect}", error.message
      end
    end
  end

  test 'max_memory: restarts the worker once it uses more memory' do
    register_rolldown(max_memory: 1)
    reference = export('main.js')
    assert_nil worker_pid

    assert_equal reference, export('main.js')
    assert_nil worker_pid
  end

  test 'the worker is restarted when the Rolldown install changes' do
    rolldown = File.realpath(File.join(@npm_dir, 'node_modules', 'rolldown'))
    file 'wrapped-rolldown/package.json', JSON.generate({ name: 'rolldown', version: '0.0.1', main: './index.js' })
    file 'wrapped-rolldown/index.js', "module.exports = require(#{JSON.generate(rolldown)});\n"
    register_rolldown(bundler_path: File.join(@path, 'wrapped-rolldown'))

    reference = export('main.js')
    pid = worker_pid
    assert_equal reference, export('main.js')
    assert_equal pid, worker_pid

    file 'wrapped-rolldown/package.json', JSON.generate({ name: 'rolldown', version: '0.0.2', main: './index.js' })
    assert_equal reference, export('main.js')
    assert_not alive?(pid)
    assert alive?(worker_pid)
    assert_not_equal pid, worker_pid
  end

  test 'a forked child starts its own worker' do
    reference = export('main.js')
    parent = worker_pid

    reader, writer = IO.pipe
    child = fork do
      reader.close
      source = export('main.js')
      writer.write(JSON.generate({ pid: worker_pid, same: source == reference }))
      writer.close
      exit!(0)
    end
    writer.close
    result = JSON.parse(reader.read)
    reader.close
    Process.wait(child)

    assert result['same']
    assert result['pid']
    assert_not_equal parent, result['pid']
    assert wait_until { !alive?(result['pid']) }

    assert_equal parent, worker_pid
    assert alive?(parent)
    assert_equal reference, export('main.js')
    assert_equal parent, worker_pid
  end

  ['TERM', 'KILL'].each do |signal|
    test "the worker exits when its ruby process is killed with #{signal}" do
      file 'child.rb', <<~RUBY
        require 'condenser'
        require 'logger'
        env = Condenser.new(#{@path.inspect}, logger: Logger.new(File::NULL), npm_path: #{@npm_dir.inspect}, base: #{@path.inspect})
        env.unregister_minifier('application/javascript')
        env.unregister_exporter('application/javascript')
        processor = Condenser::RolldownProcessor.new(#{@npm_dir.inspect})
        env.register_exporter('application/javascript', processor)
        env.find('main.js').export
        puts processor.worker.pid
        $stdout.flush
        sleep
      RUBY

      reader, writer = IO.pipe
      child = Process.spawn(Gem.ruby, '-I', File.expand_path('../../../lib', __dir__), '-rbundler/setup', File.join(@path, 'child.rb'), out: writer, err: File::NULL)
      writer.close
      line = Timeout.timeout(60) { reader.gets }
      reader.close
      worker = Integer(line)
      assert alive?(worker)

      Process.kill(signal, child)
      Process.wait(child)
      assert wait_until { !alive?(worker) }, "worker #{worker} is still running"
    ensure
      Process.kill('KILL', child) rescue nil if child
      Process.kill('KILL', worker) rescue nil if worker
    end
  end

  test 'an unchanged module is not loaded from ruby again' do
    math = File.join(@path, 'math.js')
    reference = nil
    assert_equal [File.join(@path, 'main.js'), math].sort, loads { reference = export('main.js') }.sort

    assert_empty loads { assert_equal reference, export('main.js') }
  end

  test 'an edited module is loaded again and changes the output' do
    export('main.js')
    file 'math.js', <<~JS
      export function cube ( x ) {
        return x * x * x * 1;
      }
    JS

    source = nil
    assert_equal [File.join(@path, 'math.js')], loads { source = export('main.js') }
    assert_includes source, 'x * x * x * 1'
  end

  test 'the cache is shared by entries and digests are checked per build' do
    file 'other.js', <<~JS
      import { cube } from './math.js';

      console.log( cube( 6 ) );
    JS
    export('main.js')
    assert_equal [File.join(@path, 'other.js')], loads { export('other.js') }

    file 'math.js', "export function cube ( x ) { return 'edited'; }\n"
    assert_includes export('other.js'), '"edited"'
    assert_includes export('main.js'), '"edited"'
  end

  test 'an edited entry changes the output' do
    export('main.js')
    file 'main.js', <<~JS
      import { cube } from './math.js';

      console.log( cube( 7 ) );
    JS

    source = nil
    assert_equal [File.join(@path, 'main.js')], loads { source = export('main.js') }
    assert_includes source, 'cube(7)'
  end

  test 'the export input of an entry is not served when the file is imported' do
    file 'other.js', <<~JS
      import './main.js';
    JS

    assert_includes export('main.js', source: "console.log( 'input' );\n"), '"input"'
    source = export('other.js')
    assert_includes source, 'cube(5)'
    assert_not_includes source, '"input"'
    assert_includes export('main.js', source: "console.log( 'input' );\n"), '"input"'
  end

  test 'a module that imports the entry gets the export input' do
    file 'main.js', <<~JS
      import { name } from './cycle.js';

      export const entry = 'entry';
      console.log( name );
    JS
    file 'cycle.js', <<~JS
      import { entry } from './main.js';

      export const name = 'cycle';
      console.log( entry );
    JS

    export('main.js')
    source = export('main.js', source: "import { name } from './cycle.js';\nexport const entry = 'input';\nconsole.log( name );\n")
    assert_includes source, '"input"'
    assert_not_includes source, '"entry"'
  end

  test 'edits to templated and transformed sources change the output' do
    file 'main.js', <<~JS
      import value from './value';
      import template from './template';
      import icon from './icon.svg';

      console.log( value, template({ name: 'x' }), icon );
    JS
    file 'value.js.erb', "export default '<%= 'a' * 3 %>';\n"
    file 'template.jst', <<~JS
      export default function (locals) {
          return "<b>" + name + "</b>";
      }
    JS
    file 'icon.svg', %{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"></svg>\n}

    source = export('main.js')
    assert_includes source, '"aaa"'
    assert_includes source, '"<b>"'
    assert_includes source, '"0 0 10 10"'
    assert_empty loads { export('main.js') }

    file 'value.js.erb', "export default '<%= 'b' * 3 %>';\n"
    file 'template.jst', <<~JS
      export default function (locals) {
          return "<i>" + name + "</i>";
      }
    JS
    file 'icon.svg', %{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"></svg>\n}
    source = export('main.js')
    assert_includes source, '"bbb"'
    assert_includes source, '"<i>"'
    assert_includes source, '"0 0 20 20"'
    assert_not_includes source, '"aaa"'
  end

  test 'glob and dynamic import modules are served from the cache until they change' do
    file 'main.js', <<~JS
      import maths from 'maths/*';

      console.log( maths.map((f) => f(2)), await import('./lazy.js') );
    JS
    file 'maths/a.js', "export default function a (x) { return x + 1; }\n"
    file 'maths/b.js', "export default function b (x) { return x + 2; }\n"
    file 'lazy.js', "export default 'lazy';\n"
    reference = export('main.js')
    assert_empty loads { assert_equal reference, export('main.js') }

    file 'maths/b.js', "export default function b (x) { return x + 3; }\n"
    file 'lazy.js', "export default 'lazier';\n"
    source = nil
    assert_equal [File.join(@path, 'lazy.js'), File.join(@path, 'maths/b.js')], loads { source = export('main.js') }.sort
    assert_includes source, 'x + 3'
    assert_includes source, '"lazier"'
  end

  test 'a restarted worker starts with an empty cache' do
    register_rolldown(max_builds: 1)
    export('main.js')
    assert_equal [File.join(@path, 'main.js'), File.join(@path, 'math.js')], loads { export('main.js') }.sort
  end

end
