# frozen_string_literal: true

require 'tempfile'
require 'open3'
require 'securerandom'

class Condenser
  class NodeProcessor
    
    attr_accessor :npm_path
    
    def self.setup(environment)
    end
  
    def name
      self.class.name
    end

    def self.call(environment, input)
      @instances ||= {}
      @instances[environment] ||= new(environment.npm_path)
      @instances[environment].call(environment, input)
    end
    
    def initialize(npm_dir = nil)
      self.npm_path = npm_dir
    end
    
    def exec_runtime(script)
      Tempfile.open(['script', 'js']) do |scriptfile|
        scriptfile.write(script)
        scriptfile.flush

        stdout, stderr, status = Open3.capture3(binary, scriptfile.path)
        
        if status.success?
          puts stderr if !stderr.strip.empty?
          JSON.parse(stdout)
        else
          raise exec_runtime_error(stdout + stderr)
        end
      end
    end

    # Like #exec_runtime, but keeps the node process running between calls so
    # node and the script's requires are only loaded once. +script+ must
    # define a `handle` function with `const` (so it isn't added to `global`);
    # each call passes +args+ to it and returns its JSON result. `handle` may
    # return a Promise, and calls from multiple threads can be in flight at
    # once.
    def exec_worker(script, *args)
      @workers ||= {}
      worker = (@workers[script] ||= Worker.new(binary, script))
      worker.call(*args)
    end

    class Worker

      # Requests are `[id, args]` lines on stdin. Responses are written on
      # their own line, prefixed with a token, as `[id, result]` so they can
      # be told apart from anything else the script writes to stdout.
      LOOP = <<~JS
        ;(() => {
          const token = process.env.CONDENSER_WORKER_TOKEN;
          const toError = (e) => ({ error: e instanceof Error ? [e.name, e.message, e.stack] : ['Error', String(e), ''] });
          const respond = (id, result) => {
            let json;
            try {
              json = JSON.stringify([id, result]);
            } catch (e) {
              json = JSON.stringify([id, toError(e)]);
            }
            process.stdout.write("\\n" + token + json + "\\n");
          };

          const lines = require('readline').createInterface({ input: process.stdin, crlfDelay: Infinity });
          lines.on('line', (line) => {
            const [id, args] = JSON.parse(line);
            Promise.resolve().then(() => handle(...args)).then(
              (result) => respond(id, result),
              (e) => respond(id, toError(e))
            );
          });
        })();
      JS

      def initialize(binary, script)
        @binary = binary
        @script = script
        @lock = Mutex.new       # guards @io, @pid, @pending, @next_id
        @write_lock = Mutex.new # serializes writes to @io
        @next_id = 0
      end

      def call(*args)
        response = Thread::Queue.new
        io, id = @lock.synchronize do
          start if @io.nil? || @pid != Process.pid
          @next_id += 1
          @pending[@next_id] = response
          [@io, @next_id]
        end

        begin
          @write_lock.synchronize { io.write(JSON.generate([id, args]), "\n") }
        rescue Errno::EPIPE, IOError
          # The worker exited; the reader fails every pending call, this one
          # included, once it sees the pipe close.
        end

        result = response.pop
        raise result if result.is_a?(Exception)
        result
      end

      private

      # Started lazily, and again after a fork, so a forked process never
      # shares its parent's pipe.
      def start
        @scriptfile = Tempfile.new(['worker', '.js'])
        @scriptfile.write(@script, "\n", LOOP)
        @scriptfile.flush
        @pid = Process.pid
        @pending = {}
        token = "#{SecureRandom.hex(8)}:"
        @io = IO.popen({ 'CONDENSER_WORKER_TOKEN' => token }, [@binary, @scriptfile.path], 'r+')
        Thread.new(@io, token, @pending) { |io, t, pending| read_responses(io, t, pending) }
      end

      def read_responses(io, token, pending)
        while line = io.gets
          if line.start_with?(token)
            id, result = JSON.parse(line.delete_prefix(token))
            @lock.synchronize { pending.delete(id) }&.push(result)
          elsif !line.strip.empty?
            $stdout.write(line)
          end
        end
      ensure
        begin
          io.close
        rescue IOError
        end
        status = $?

        @lock.synchronize do
          @io = nil if @io.equal?(io)
          error = RuntimeError.new("node worker exited unexpectedly#{" (#{status})" if status}")
          pending.each_value { |q| q.push(error) }
          pending.clear
        end
      end

    end

    def binary(cmd='node')
      if File.executable? cmd
        cmd
      else
        path = ENV['PATH'].split(File::PATH_SEPARATOR).find { |p|
          full_path = File.join(p, cmd)
          File.executable?(full_path) && File.file?(full_path)
        }
        if path.nil?
          raise Condenser::CommandNotFoundError, "Could not find executable #{cmd}"
        end
        File.expand_path(cmd, path)
      end
    end
    
    def exec_syntax_error(output, source_file)
      error = Condenser::SyntaxError.new(output)
      lines = output.split("\n")
      lineno = lines[0][/\((\d+):\d+\)$/, 1] if lines[0]
      lineno ||= 1
      error.set_backtrace(["#{source_file}:#{lineno}"] + caller)
      error.instance_variable_set(:@path, source_file)
      error
    end
    
    def exec_runtime_error(output)
      error = RuntimeError.new(output)
      lines = output.split("\n")
      lineno = lines[0][/:(\d+)$/, 1] if lines[0]
      lineno ||= 1
      error.set_backtrace(["(node):#{lineno}"] + caller)
      error
    end
    
    def npm_install(*packages)
      return if packages.empty?
      packages.flatten!
      packages.select! do |package|
        !Dir.exist?(File.join(npm_module_path, package))
      end
      
      Dir.chdir(npm_path) do
        if !packages.empty?
          if File.exist?(File.join(npm_path, 'package.json'))
            system("npm", "install", "--silent", *packages)
          else
            system("npm", "install", "--silent", *packages)
          end
        end
      end
    end
    
    def npm_module_path(package=nil)
      File.join(*[npm_path, 'node_modules', package].compact)
    end
    
  end
end