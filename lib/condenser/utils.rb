class Condenser
  module Utils

    # Public: Write to a file atomically. Useful for situations where you
    # don't want other processes or threads to see half-written files.
    #
    #   Utils.atomic_write('important.file') do |file|
    #     file.write('hello')
    #   end
    #
    # Returns nothing.
    def self.atomic_write(filename)
      dirname, basename = File.split(filename)
      basename = [
        basename,
        Thread.current.object_id,
        Process.pid,
        rand(1000000)
      ].join('.'.freeze)
      tmpname = File.join(dirname, basename)

      File.open(tmpname, 'wb+') do |f|
        yield f
      end

      File.rename(tmpname, filename)
    ensure
      File.delete(tmpname) if File.exist?(tmpname)
    end
    
    # Internal: Inject into target module for the duration of the block.
    #
    # mod - Module
    #
    # Returns result of block.
    def self.module_include(base, mod)
      old_methods = {}

      mod.instance_methods.each do |sym|
        old_methods[sym] = base.instance_method(sym) if base.method_defined?(sym)
      end

      mod.instance_methods.each do |sym|
        method = mod.instance_method(sym)
        base.send(:define_method, sym, method)
      end

      yield
    ensure
      mod.instance_methods.each do |sym|
        base.send(:undef_method, sym) if base.method_defined?(sym)
      end
      old_methods.each do |sym, method|
        base.send(:define_method, sym, method)
      end
    end
    
  end
end
