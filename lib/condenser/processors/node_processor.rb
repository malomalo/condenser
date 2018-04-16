require 'tempfile'

class Condenser
  class NodeProcessor
    
    def exec_runtime(script)
      Tempfile.open(['script', 'js']) do |scriptfile|
        scriptfile.write(script)
        scriptfile.flush
        io = IO.popen([binary, scriptfile.path], err: [:child, :out])
        output = io.read
        io.close
        
        if $?.success?
          JSON.parse(output)
        else
          raise exec_runtime_error(output)
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
        path && File.expand_path(cmd, path)
      end
    end
    
    def exec_runtime_error(output)
      error = RuntimeError.new(output)
      lines = output.split("\n")
      lineno = lines[0][/:(\d+)$/, 1] if lines[0]
      lineno ||= 1
      error.set_backtrace(["(node):#{lineno}"] + caller)
      error
    end
    
  end
end