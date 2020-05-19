require 'tempfile'
require 'open3'

class Condenser
  class NodeProcessor
    
    attr_accessor :npm_path
    
    def self.setup(environment)
    end

    def self.call(environment, input)
      @instances ||= {}
      @instances[environment] ||= new(environment.npm_path)
      @instances[environment].call(environment, input)
    end
    
    def initialize(dir = nil)
      self.npm_path = dir
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