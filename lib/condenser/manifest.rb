class Condenser
  class Manifest
    
    attr_reader :filename, :dir, :environment, :logger
    
    def initialize(*args)
      args.compact!
      
      if args.first.is_a?(Condenser)
        @environment = args.shift
        @logger = @environment.logger
      else
        @environment = nil
        @logger = Logger.new($stdout, level: :info)
      end
      
      @dir, @filename = args[0], args[1]
      
      # Expand paths
      @dir = File.expand_path(@dir) if @dir
      @filename  = File.expand_path(@filename) if @filename
      
      # If filename is given as the second arg
      if @dir && File.extname(@dir) != ""
        @dir, @filename = nil, @dir
      end
      
      # Default dir to the directory of the filename
      @dir ||= File.dirname(@filename) if @filename
      
      # If directory is given w/o filename, pick a random manifest location
      if @dir && @filename.nil?
        @filename = File.join(@dir, 'manifest.json')
      end
      
      unless @dir && @filename
        raise ArgumentError, "manifest requires output filename"
      end
      
      if File.exist?(@filename)
        begin
          @data = JSON.parse(File.read(@filename))
        rescue JSON::ParserError => e
          @data = {}
          logger.error "#{@filename} is invalid: #{e.class} #{e.message}"
        end
      else
        @data = {}
      end
    end
    
    def reset
      @data = {}
    end
    
    def add(*args)
      if @environment.nil?
        raise Error, "manifest requires environment for compilation"
      end
      
      outputs = []
      args.each do |arg|
        @environment.resolve(arg).each do |asset|
          outputs += add_asset(asset)
        end
      end
    end
    
    def add_asset(asset)
      export = asset.export

      @data[asset.filename] = export.to_json
      outputs = export.write(@dir)
      asset.linked_assets.each do |la|
        @environment.resolve(la).each { |a| outputs += add_asset(a) }
      end
      outputs
    end
    
    def [](key)
      add(key) if @environment
      @data[key]
    end
    
    def compile(*args)
      reset
      outputs = add(*args.flatten)
      save
      outputs
    end
    
    # Persist manfiest back to FS
    def save
      return if @filename.nil?
      FileUtils.mkdir_p File.dirname(@filename)
      Utils.atomic_write(@filename) { |f| f.write(JSON.generate(@data)) }
    end
    
    def export(*args)
      add(*args)
      save
    end
    
    # Cleanup old assets in the compile directory. By default it will keep the
    # latest version and remove any other files over 4 weeks old.
    def clean(age = 2419200)
      clean_dir(@dir, @data.values.map{ |v| v['path'] }, Time.now - age)
    end

    def clean_dir(dir, assets, age)
      Dir.each_child(dir) do |child|
        child = File.join(dir, child)
        next if assets.find { |x| child.start_with?(x) }

        if File.directory?(child)
          clean_dir(dir, assets, age)
        elsif File.file?(child) && File.stat(child).mtime < age
          File.delete(child)
        end
      end
    end

    # Wipe directive
    def clobber
      return if !Dir.exist?(dir)
      
      FileUtils.rm(filename)
      logger.info "Removed #{filename}"
      
      Dir.each_child(dir) do |child|
        FileUtils.rm_r(File.join(dir, child))
      end
      
      logger.info "Removed contents of #{dir}"
      nil
    end

  end
end