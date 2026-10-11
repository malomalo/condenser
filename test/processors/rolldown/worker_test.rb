require 'test_helper'

class RolldownWorkerTest < ActiveSupport::TestCase

  module AnswerSpy
    def answer(method, *args)
      RolldownWorkerTest.on_answer&.call(method, args, self)
      super
    end
  end
  Condenser::RolldownProcessor::Runner.prepend(AnswerSpy)

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
  def export(name, processor: @processor)
    asset = @env.find(name)
    input = { source: asset.source.dup, source_file: asset.source_file, filename: asset.filename.dup, content_types: asset.content_types, map: nil }
    processor.call(@env, input)[:source]
  end

  def worker_pids
    Condenser::RolldownProcessor::Worker.workers.filter_map(&:pid)
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

  test 'exports reuse one worker' do
    reference = export('main.js')
    assert_includes reference, 'x * x * x'
    pids = worker_pids
    assert_equal 1, pids.size

    assert_equal reference, export('main.js')
    assert_equal pids, worker_pids
  end

  test 'a processor registered as a class shares the worker' do
    register_rolldown(Condenser::RolldownProcessor)
    reference = export('main.js')
    pids = worker_pids

    assert_equal reference, export('main.js')
    assert_equal reference, export('main.js', processor: Condenser::RolldownProcessor.new(@env.npm_path))
    assert_equal pids, worker_pids
    assert_equal 1, pids.size
  end

  test 'differently configured processors share the worker' do
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
    assert_equal 1, worker_pids.size
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
    pid = worker_pids.first
    Process.kill('KILL', pid)

    assert_equal reference, export('main.js')
    assert_not_equal [pid], worker_pids
    assert_not alive?(pid)
  end

  test 'a worker killed during an export is replaced and the export retried once' do
    reference = export('main.js')
    killed = []
    on_answer do |method, _, _|
      if method == 'load' && killed.empty?
        killed << worker_pids.first
        Process.kill('KILL', killed.first)
      end
    end

    assert_equal reference, export('main.js')
    assert_equal 1, killed.size
    assert_not_equal killed, worker_pids
    assert_not alive?(killed.first)
  end

  test 'a worker that dies on the retry too raises an error' do
    export('main.js')
    killed = []
    on_answer do |method, _, _|
      if method == 'load'
        killed << worker_pids.first
        Process.kill('KILL', killed.last)
      end
    end

    error = assert_raises(RuntimeError) { export('main.js') }
    assert_match(/\Arolldown exited with pid \d+ SIGKILL/, error.message)
    assert_equal 2, killed.size
    assert_empty worker_pids
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
    assert_empty worker_pids
  ensure
    ENV['NODE_OPTIONS'] = node_options
  end

  test 'stop_workers stops the worker' do
    reference = export('main.js')
    pid = worker_pids.first

    Condenser::RolldownProcessor.stop_workers
    assert_not alive?(pid)
    assert_empty worker_pids

    assert_equal reference, export('main.js')
    assert_not_equal [pid], worker_pids
  end

  test 'a ruby exception while answering re-raises the original exception and keeps the worker' do
    file 'main.js', <<~JS
      import maths from 'maths/*';

      console.log( maths.map((f) => f(2)) );
    JS
    5.times { |i| file "maths/f#{i}.js", "export default function f#{i} (x) { return x + #{i}; }\n" }
    reference = export('main.js')
    pid = worker_pids.first

    on_answer do |method, args, _|
      raise ArgumentError, 'boom' if method == 'load' && args[0].end_with?('f2.js')
    end
    error = assert_raises(ArgumentError) { export('main.js') }
    assert_equal 'boom', error.message
    assert_equal [pid], worker_pids

    answered = []
    on_answer { |method, args, runner| answered << [method, args, runner] }
    assert_equal reference, export('main.js')
    assert_equal [pid], worker_pids
    assert_equal 1, answered.map(&:last).uniq.size

    clean = answered.map { |method, args, _| [method, args] }
    answered.clear
    export('main.js')
    assert_equal clean.sort, answered.map { |method, args, _| [method, args] }.sort
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
    pid = worker_pids.first

    on_answer { |method, _, _| raise Abort if method == 'load' }
    assert_raises(Abort) { export('main.js') }
    assert_not alive?(pid)
    assert_empty worker_pids

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
    pids = worker_pids

    results = 4.times.map { |i| Thread.new { export(i.even? ? 'main.js' : 'other.js') } }.map(&:value)
    assert_equal 4.times.map { |i| references[i.even? ? 'main.js' : 'other.js'] }, results
    assert_equal pids, worker_pids
  end

  test 'an export started while answering a build uses another worker' do
    file 'other.js', <<~JS
      console.log( 'other' );
    JS
    nested = nil
    on_answer do |method, args, _|
      if method == 'load' && args[0].end_with?('math.js') && nested.nil?
        nested = Timeout.timeout(30) { export('other.js') }
      end
    end

    assert_includes export('main.js'), 'x * x * x'
    assert_includes nested, 'console.log("other")'
    assert_equal 2, worker_pids.size
  end

  test 'max_builds: restarts the worker after that many builds' do
    register_rolldown(max_builds: 2)
    reference = export('main.js')
    first = worker_pids

    assert_equal reference, export('main.js')
    assert_empty worker_pids
    assert_not alive?(first.first)

    assert_equal reference, export('main.js')
    assert_equal 1, worker_pids.size
    assert_not_equal first, worker_pids
  end

  test 'max_memory: restarts the worker once it uses more memory' do
    register_rolldown(max_memory: 1)
    reference = export('main.js')
    assert_empty worker_pids

    assert_equal reference, export('main.js')
    assert_empty worker_pids
  end

  test 'the worker is restarted when the Rolldown install changes' do
    rolldown = File.realpath(File.join(@npm_dir, 'node_modules', 'rolldown'))
    file 'wrapped-rolldown/package.json', JSON.generate({ name: 'rolldown', version: '0.0.1', main: './index.js' })
    file 'wrapped-rolldown/index.js', "module.exports = require(#{JSON.generate(rolldown)});\n"
    register_rolldown(bundler_path: File.join(@path, 'wrapped-rolldown'))

    reference = export('main.js')
    pid = worker_pids.first
    assert_equal reference, export('main.js')
    assert_equal [pid], worker_pids

    file 'wrapped-rolldown/package.json', JSON.generate({ name: 'rolldown', version: '0.0.2', main: './index.js' })
    assert_equal reference, export('main.js')
    assert_not alive?(pid)
    assert_equal 1, worker_pids.size
    assert_not_equal [pid], worker_pids
  end

  test 'a forked child starts its own worker' do
    reference = export('main.js')
    parent = worker_pids

    reader, writer = IO.pipe
    child = fork do
      reader.close
      source = export('main.js')
      writer.write(JSON.generate({ pids: worker_pids, same: source == reference }))
      writer.close
      exit!(0)
    end
    writer.close
    result = JSON.parse(reader.read)
    reader.close
    Process.wait(child)

    assert result['same']
    assert_equal 1, result['pids'].size
    assert_not_equal parent, result['pids']
    assert wait_until { !alive?(result['pids'].first) }

    assert_equal parent, worker_pids
    assert alive?(parent.first)
    assert_equal reference, export('main.js')
    assert_equal parent, worker_pids
  end

  ['TERM', 'KILL'].each do |signal|
    test "the worker exits when its ruby process is killed with #{signal}" do
      file 'child.rb', <<~RUBY
        require 'condenser'
        require 'logger'
        env = Condenser.new(#{@path.inspect}, logger: Logger.new(File::NULL), npm_path: #{@npm_dir.inspect}, base: #{@path.inspect})
        env.unregister_minifier('application/javascript')
        env.unregister_exporter('application/javascript')
        env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(#{@npm_dir.inspect}))
        env.find('main.js').export
        puts Condenser::RolldownProcessor::Worker.workers.map(&:pid).join(' ')
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

end
