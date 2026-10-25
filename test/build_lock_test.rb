require 'test_helper'

class BuildLockTest < ActiveSupport::TestCase

  THREADS = 10
  TIMEOUT = 10

  def setup
    super
    skip 'needs a listening build cache' unless @env.build_cache.listening
  end

  # Runs the block on THREADS threads at once and fails, instead of hanging,
  # if any of them doesn't finish within TIMEOUT seconds. The threads stay
  # alive until all are done, like a server's thread pool, since Ruby
  # releases the mutexes a thread holds when it exits.
  def concurrently(&block)
    ready = Queue.new
    go = Queue.new
    done = Queue.new
    release = Queue.new
    threads = THREADS.times.map do |i|
      Thread.new do
        ready << true
        go.pop
        done << [i, block.call(i)]
        release.pop
      end
    end
    THREADS.times { ready.pop }
    THREADS.times { go << true }

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT
    results = []
    THREADS.times do
      result = done.pop(timeout: [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max) or break
      results << result
    end
    assert_equal THREADS, results.size, "#{THREADS - results.size} of #{THREADS} threads never finished"
    results.sort_by(&:first).map(&:last)
  ensure
    THREADS.times { release << true }
    threads&.each { |t| t.join(1) || t.kill }
  end

  test 'concurrent builds on a listening environment all finish' do
    results = concurrently do |i|
      @env.build { sleep 0.01; i }
    end

    assert_equal THREADS.times.to_a, results
    assert_not @env.build_cache.semaphore.locked?
  end

  test 'concurrent exports on a listening environment all finish' do
    file 'x.js', "export default function x() { return 1; }\n"

    results = concurrently { @env.find('x.js').export.source }

    assert_equal 1, results.uniq.size
    assert_not @env.build_cache.semaphore.locked?
  end

  test 'concurrent first use of an environment creates one build cache' do
    env = Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path)

    caches = concurrently { env.build_cache }
    assert_equal 1, caches.map(&:object_id).uniq.size
    assert_same env.build_cache, caches.first

    concurrently { |i| env.build { sleep 0.01; i } }
    assert_not env.build_cache.semaphore.locked?
  ensure
    caches&.uniq&.each { |cache| cache.instance_variable_get(:@listener)&.stop }
  end

  test 'a nested build on the same thread keeps the lock until the outermost build ends' do
    semaphore = @env.build_cache.semaphore
    @env.build do
      @env.build do
        assert semaphore.owned?
        @env.build { assert semaphore.owned? }
      end
      assert semaphore.owned?
    end
    assert_not semaphore.locked?

    assert_equal [:other], concurrently { @env.build { :other } }.uniq
  end

  test 'a build that raises while starting unlocks for other threads' do
    @env.build_cache.stubs(:clear_if_npm_changed).raises(Errno::EACCES).then.returns(nil)
    assert_raises(Errno::EACCES) { @env.build { } }
    assert_not @env.build_cache.semaphore.locked?

    assert_equal THREADS.times.to_a, concurrently { |i| @env.build { i } }
  end

end
