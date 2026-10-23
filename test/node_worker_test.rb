require 'test_helper'

class CondenserNodeWorkerTest < ActiveSupport::TestCase

  module SpawnSpy
    def spawn(*args, **kwargs)
      super.tap { |pid| Thread.current[:node_worker_spawns]&.push([pid, args]) }
    end
  end
  Process.singleton_class.prepend(SpawnSpy)

  class Abort < Exception; end

  # Asks Ruby each of config.ask in turn and is done with what it answered.
  # config.stale sends a request, a warning and a result for the previous
  # build first, and config.partial dies halfway through writing a line.
  SCRIPT = <<~JS
    const net = require('net');
    const readline = require('readline');

    const channel = new net.Socket({ fd: 3 });
    channel.on('error', () => process.exit(1));
    let rid = 0;
    const pending = new Map();

    function send(message) {
      channel.write(JSON.stringify(message) + "\\n");
    }

    function request(build, method, args) {
      const id = rid++;
      return new Promise((resolve, reject) => {
        pending.set(id, (message) => message.error === undefined ? resolve(message['return']) : reject(new Error(message.error)));
        send({ rid: id, build, method, args });
      });
    }

    async function run(build, config) {
      if (config.partial) {
        require('fs').writeSync(3, '{"method":"do');
        process.exit(1);
      }
      if (config.stale) {
        send({ rid: 1e9, build: build - 1, method: 'stale', args: [] });
        send({ method: 'warn', build: build - 1, args: ['stale warning'] });
        send({ method: 'done', build: build - 1, args: ['stale result'] });
      }
      if (config.warn) send({ method: 'warn', build, args: [config.warn] });
      const answers = [];
      for (const [method, ...args] of config.ask || []) answers.push(await request(build, method, args));
      return { pid: process.pid, argument: process.argv[2], execArgv: process.execArgv, answers };
    }

    let queue = Promise.resolve();
    readline.createInterface({ input: channel, crlfDelay: Infinity }).on('line', (line) => {
      const message = JSON.parse(line);
      if (message.rid !== undefined) {
        const settle = pending.get(message.rid);
        pending.delete(message.rid);
        settle?.(message);
      } else if (message.build !== undefined) {
        queue = queue.then(() => run(message.build, message.config).then(
          (result) => send({ method: 'done', build: message.build, args: [result], rss: process.memoryUsage.rss() }),
          (e) => send({ method: 'error', build: message.build, args: [e.name, e.message, e.stack], rss: process.memoryUsage.rss() })
        ));
      }
    }).on('close', () => process.exit(0));
  JS

  def setup
    super
    file 'worker.js', SCRIPT
    @script = File.join(@path, 'worker.js')
    @binary = Condenser::NodeProcessor.new(@npm_dir).binary
    @log = StringIO.new
    @logger = Logger.new(@log, level: :warn)
    @worker = new_worker
  end

  def teardown
    Thread.current[:node_worker_spawns] = nil
    super
  end

  def new_worker(**options)
    Condenser::NodeWorker.new(@binary, 'the-argument', script: @script, name: 'test', **options)
  end

  def build(config = {}, worker: @worker, &block)
    worker.build(config, logger: @logger, &block)
  end

  def result(config = {}, worker: @worker, &block)
    message = build(config, worker: worker, &block)
    assert_equal 'done', message['method'], message.inspect
    message['args'][0]
  end

  def alive?(pid)
    Process.kill(0, pid) == 1
  rescue Errno::ESRCH
    false
  end

  test 'script:, name: are required' do
    assert_raises(ArgumentError) { Condenser::NodeWorker.new(@binary, 'x', name: 'test') }
    assert_raises(ArgumentError) { Condenser::NodeWorker.new(@binary, 'x', script: @script) }
  end

  test 'runs the script with the argument and answers its requests' do
    answer = result({ ask: [['add', 1, 2], ['add', 3, 4]] }) { |method, args| { method => args.sum } }
    assert_equal 'the-argument', answer['argument']
    assert_equal [{ 'add' => 3 }, { 'add' => 7 }], answer['answers']
    assert_equal @worker.pid, answer['pid']
    assert_equal @worker.pid, result['pid']
  end

  test 'max_old_space_size: is passed to node only when given' do
    spawns = Thread.current[:node_worker_spawns] = []

    assert_empty result['execArgv']
    assert_equal [@binary, @script, 'the-argument'], spawns.last[1]

    sized = new_worker(max_old_space_size: 64)
    assert_equal ['--max_old_space_size=64'], result(worker: sized)['execArgv']
    assert_equal [@binary, '--max_old_space_size=64', @script, 'the-argument'], spawns.last[1]
  ensure
    sized&.stop
  end

  test 'warnings for the build are logged' do
    result({ warn: 'a warning' })
    assert_includes @log.string, 'a warning'
  end

  test 'a worker killed during a build raises WorkerDied and the next build starts another' do
    pid = nil
    error = assert_raises(Condenser::NodeWorker::WorkerDied) do
      build({ ask: [['kill']] }) do
        pid = @worker.pid
        Process.kill('KILL', pid)
      end
    end
    assert_match(/\Atest exited with pid #{pid} SIGKILL/, error.message)
    assert_nil @worker.pid
    assert_not alive?(pid)

    assert_not_equal pid, result['pid']
  end

  test 'a partial last line from a worker that died mid-write is not parsed' do
    error = assert_raises(Condenser::NodeWorker::WorkerDied) { build({ partial: true }) }
    assert_match(/\Atest exited with pid \d+ exit 1/, error.message)
    assert_nil @worker.pid
  end

  test 'a worker reaped elsewhere exits with an unknown status' do
    error = assert_raises(Condenser::NodeWorker::WorkerDied) do
      build({ ask: [['kill']] }) do
        pid = @worker.pid
        Process.kill('KILL', pid)
        Process.wait(pid)
      end
    end
    assert_equal 'test exited with an unknown status', error.message
  end

  test 'stop_workers stops the worker' do
    pid = result['pid']

    Condenser::NodeWorker.stop_workers
    assert_not alive?(pid)
    assert_nil @worker.pid

    assert_not_equal pid, result['pid']
  end

  test 'a forked child that never builds does not slow down stopping the worker' do
    pid = result['pid']
    child = fork { sleep }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Condenser::NodeWorker.stop_workers
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
    assert_not alive?(pid)
  ensure
    if child
      Process.kill('KILL', child)
      Process.wait(child)
    end
  end

  test 'stop waits for the build in flight' do
    pid = result['pid']
    answering = Queue.new
    release = Queue.new

    build = Thread.new do
      result({ ask: [['wait']] }) do
        answering << true
        release.pop
      end
    end
    answering.pop
    stopper = Thread.new { @worker.stop }
    assert wait_until { stopper.status == 'sleep' }
    assert alive?(pid)

    release << 'released'
    assert_equal ['released'], build.value['answers']
    stopper.join
    assert_not alive?(pid)
    assert_nil @worker.pid
    assert @worker.stopping?
  end

  test 'a ruby exception while answering re-raises the original exception and keeps the worker' do
    pid = result['pid']

    error = assert_raises(ArgumentError) do
      build({ ask: [['a'], ['b']] }) { |method, _| raise ArgumentError, 'boom' if method == 'a' }
    end
    assert_equal 'boom', error.message
    assert_equal pid, @worker.pid
    assert alive?(pid)

    assert_equal pid, result['pid']
  end

  test 'a ruby exception is re-raised when the worker then dies' do
    pid = result['pid']

    error = assert_raises(ArgumentError) do
      build({ ask: [['a']] }) do
        Process.kill('KILL', pid)
        Process.wait(pid)
        raise ArgumentError, 'boom'
      end
    end
    assert_equal 'boom', error.message
    assert_nil @worker.pid
  end

  test 'an exception that abandons a build stops the worker' do
    pid = result['pid']

    assert_raises(Abort) { build({ ask: [['a']] }) { raise Abort } }
    assert_not alive?(pid)
    assert_nil @worker.pid

    assert result['pid']
  end

  test 'requests, warnings and results from an earlier build are ignored' do
    result
    asked = []
    answer = result({ stale: true, ask: [['current']] }) { |method, _| asked << method; 'answer' }
    assert_equal ['current'], asked
    assert_equal ['answer'], answer['answers']
    assert_not_includes @log.string, 'stale warning'
  end

  test 'concurrent builds share the worker one build at a time' do
    pid = result['pid']
    lock = Mutex.new
    active = 0
    most = 0

    results = 4.times.map do |i|
      Thread.new do
        result({ ask: [['n', i]] }) do |_, args|
          lock.synchronize { most = [most, active += 1].max }
          sleep 0.01
          lock.synchronize { active -= 1 }
          args[0]
        end
      end
    end.map(&:value)

    assert_equal [[0], [1], [2], [3]], results.map { |r| r['answers'] }
    assert_equal [pid], results.map { |r| r['pid'] }.uniq
    assert_equal 1, most
  end

  test 'a build started while answering a build uses a throwaway worker' do
    pid = result['pid']
    spawns = Thread.current[:node_worker_spawns] = []
    nested = nil

    outer = result({ ask: [['nest']] }) do
      nested = Timeout.timeout(30) { result }
      nil
    end
    assert_equal pid, outer['pid']
    assert_equal 1, spawns.size
    assert_equal spawns[0][0], nested['pid']
    assert_not_equal pid, nested['pid']
    assert_not alive?(nested['pid'])
    assert alive?(pid)
  end

  test 'max_memory: restarts the worker once it uses more memory' do
    worker = new_worker(max_memory: 1)
    first = result(worker: worker)['pid']
    assert_nil worker.pid
    assert_not alive?(first)

    assert_not_equal first, result(worker: worker)['pid']
    assert_nil worker.pid
  end

  test 'a forked child starts its own worker' do
    parent = result['pid']

    reader, writer = IO.pipe
    child = fork do
      reader.close
      writer.write(JSON.generate({ pid: result['pid'], worker: @worker.pid }))
      writer.close
      exit!(0)
    end
    writer.close
    forked = JSON.parse(reader.read)
    reader.close
    Process.wait(child)

    assert forked['pid']
    assert_equal forked['pid'], forked['worker']
    assert_not_equal parent, forked['pid']
    assert wait_until { !alive?(forked['pid']) }

    assert_equal parent, @worker.pid
    assert alive?(parent)
    assert_equal parent, result['pid']
  end

  ['TERM', 'KILL'].each do |signal|
    test "the worker exits when its ruby process is killed with #{signal}" do
      file 'child.rb', <<~RUBY
        require 'condenser'
        require 'logger'
        worker = Condenser::NodeWorker.new(#{@binary.inspect}, 'x', script: #{@script.inspect}, name: 'test')
        worker.build({}, logger: Logger.new(File::NULL))
        puts worker.pid
        $stdout.flush
        sleep
      RUBY

      log = File.join(@path, 'child.log')
      reader, writer = IO.pipe
      child = Process.spawn(Gem.ruby, '-I', File.expand_path('../lib', __dir__), '-rbundler/setup', File.join(@path, 'child.rb'), out: writer, err: log)
      writer.close
      line = Timeout.timeout(60) { reader.gets }
      reader.close
      flunk "the child exited without printing its worker's pid:\n#{File.read(log)}" if line.nil?
      worker = Integer(line)
      assert alive?(worker), File.read(log)

      Process.kill(signal, child)
      Process.wait(child)
      assert wait_until { !alive?(worker) }, "worker #{worker} is still running:\n#{File.read(log)}"
    ensure
      Process.kill('KILL', child) rescue nil if child
      Process.kill('KILL', worker) rescue nil if worker
    end
  end

end
