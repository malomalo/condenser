require 'tempfile'
require 'open3'

class Condenser
  class NodeProcessor
    
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