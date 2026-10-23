# frozen_string_literal: true

require 'json'
require 'socket'

# A node process running +script+ with +argument+ that runs one build at a
# time, over a Unix socket on fd 3.
class Condenser::NodeWorker

  MAX_MEMORY = 1536 * 1024 * 1024

  class WorkerDied < RuntimeError; end

  @workers = ObjectSpace::WeakMap.new

  def self.stop_workers
    @workers.each_key(&:stop)
  end

  def self.track(worker)
    @workers[worker] = true
  end

  at_exit { stop_workers }

  attr_reader :pid

  # max_old_space_size: - Node's --max_old_space_size, in MB. Without it no
  #                       flag is passed.
  def initialize(binary, argument, script:, name:, max_memory: MAX_MEMORY, max_old_space_size: nil)
    @binary = binary
    @argument = argument
    @script = script
    @name = name
    @max_memory = max_memory
    @max_old_space_size = max_old_space_size
    @lock = Mutex.new
    @next_build = 0
    self.class.track(self)
  end

  # Yields each hook request as (method, args) and returns the build's
  # 'done' or 'error' message. An exception from the block is re-raised
  # once the build has finished or the worker has died.
  def build(config, logger:, &block)
    return throwaway_build(config, logger: logger, &block) if @lock.owned?

    @lock.synchronize do
      start if @pid.nil? || @owner != Process.pid
      id = (@next_build += 1)
      @failure = nil
      message = nil

      begin
        write({ build: id, config: config })
        while (line = @io.gets)&.end_with?("\n")
          break if (message = receive(JSON.parse(line), id, logger, &block))
        end
      rescue Errno::EPIPE, Errno::ECONNRESET, IOError
        nil
      end
      raise @failure if @failure
      raise WorkerDied, exited unless message

      message
    ensure
      terminate if !message || message['rss'].to_i > @max_memory
    end
  end

  def stop
    @stopping = true
    @lock.synchronize { terminate }
  end

  def stopping?
    @stopping
  end

  private

  # Answers a hook request or logs a warning, and returns this build's
  # 'done' or 'error' message.
  def receive(message, id, logger, &block)
    if message.key?('rid')
      write({ rid: message['rid'], **reply(message, id, &block) })
    elsif message['build'] == id
      case message['method']
      when 'warn' then logger.warn(message['args'][0])
      when 'done', 'error' then return message
      end
    end
    nil
  end

  def reply(message, id)
    return { error: 'stale build' } if message['build'] != id

    { return: yield(message['method'], message['args']) }
  rescue StandardError, ScriptError => e
    @failure ||= e
    { error: "#{e.class}: #{e.message}" }
  end

  def exited
    "#{@name} exited with #{terminate || 'an unknown status'}"
  end

  def throwaway_build(config, logger:, &block)
    worker = self.class.new(@binary, @argument, script: @script, name: @name, max_memory: @max_memory, max_old_space_size: @max_old_space_size)
    worker.build(config, logger: logger, &block)
  ensure
    worker.stop
  end

  def start
    terminate
    @stopping = false
    io, child_io = UNIXSocket.pair
    begin
      flags = @max_old_space_size ? ["--max_old_space_size=#{@max_old_space_size}"] : []
      @pid = Process.spawn(@binary, *flags, @script, @argument, in: File::NULL, 3 => child_io)
    rescue Exception
      io.close
      raise
    ensure
      child_io.close
    end
    @io = io
    @owner = Process.pid
  end

  def terminate
    io, pid = @io, @pid
    @io = @pid = nil
    io&.close
    reap(pid) if pid && @owner == Process.pid
  end

  def write(message)
    @io.write(JSON.generate(message), "\n")
  end

  def reap(pid)
    Process.kill('TERM', pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    until (_, status = Process.wait2(pid, Process::WNOHANG))
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        Process.kill('KILL', pid)
        return Process.wait2(pid)[1]
      end
      sleep 0.005
    end
    status
  rescue Errno::ECHILD, Errno::ESRCH
    nil
  end
end
