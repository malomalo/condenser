require 'test_helper'

class NodeWorkerTest < ActiveSupport::TestCase

  def setup
    super
    @node = Condenser::NodeProcessor.new(@npm_dir)
  end

  test 'returns the result of handle' do
    assert_equal({ 'sum' => 3 }, @node.exec_worker(<<~JS, 1, 2))
      const handle = (a, b) => ({ sum: a + b });
    JS
  end

  test 'reuses the node process between calls' do
    script = "const handle = () => process.pid;"
    assert_equal @node.exec_worker(script), @node.exec_worker(script)
  end

  test 'errors thrown by handle are returned and the worker keeps running' do
    script = <<~JS
      const handle = (x) => {
        if (x === 'throw') { throw new TypeError('bad input'); }
        if (x === 'reject') { return Promise.reject(new RangeError('async bad')); }
        return x;
      };
    JS

    assert_equal ['TypeError', 'bad input'], @node.exec_worker(script, 'throw')['error'][0, 2]
    assert_equal ['RangeError', 'async bad'], @node.exec_worker(script, 'reject')['error'][0, 2]
    assert_equal 'ok', @node.exec_worker(script, 'ok')
  end

  test 'a result that cannot be serialized is returned as an error' do
    script = <<~JS
      const handle = (x) => {
        if (x === 'circular') { const o = {}; o.self = o; return o; }
        return x;
      };
    JS

    assert_equal 'TypeError', @node.exec_worker(script, 'circular')['error'][0]
    assert_equal 'ok', @node.exec_worker(script, 'ok')
  end

  test 'other output on stdout is passed through and not mistaken for a response' do
    script = <<~JS
      const handle = (x) => {
        console.log('chatty ' + x);
        process.stdout.write('partial line');
        return x;
      };
    JS

    out, _ = capture_io do
      assert_equal 1, @node.exec_worker(script, 1)
      assert_equal 2, @node.exec_worker(script, 2)
    end
    assert_includes out, 'chatty 1'
    assert_includes out, 'chatty 2'
  end

  test 'concurrent calls get their own responses when they finish out of order' do
    script = <<~JS
      const handle = (x, delay) => new Promise((resolve) => setTimeout(() => resolve(x), delay));
    JS

    results = [[1, 300], [2, 200], [3, 100], [4, 0]].map do |x, delay|
      Thread.new { @node.exec_worker(script, x, delay) }
    end.map(&:value)

    assert_equal [1, 2, 3, 4], results
  end

  test 'raises if the worker exits during a call and restarts on the next call' do
    script = <<~JS
      const handle = (x) => { if (x === 'exit') { process.exit(1); } return x; };
    JS

    error = assert_raises(RuntimeError) { @node.exec_worker(script, 'exit') }
    assert_match(/node worker exited unexpectedly/, error.message)
    assert_equal 'ok', @node.exec_worker(script, 'ok')
  end

  test 'restarts the worker if it dies between calls' do
    script = "const handle = () => process.pid;"
    pid = @node.exec_worker(script)

    Process.kill('KILL', pid)
    sleep 0.5

    new_pid = @node.exec_worker(script)
    assert_not_equal pid, new_pid
    assert_equal new_pid, @node.exec_worker(script)
  end

end
