class Condenser
  class Manifest
    
    attr_reader :filename, :directory
    
    def initialize(*args)
      if args.first.is_a?(Condenser)
        @environment = args.shift
      end
      
      @directory, @filename = args[0], args[1]
      
      # Expand paths
      @directory = File.expand_path(@directory) if @directory
      @filename  = File.expand_path(@filename) if @filename
      
      # If filename is given as the second arg
      if @directory && File.extname(@directory) != ""
        @directory, @filename = nil, @directory
      end

      # Default dir to the directory of the filename
      @directory ||= File.dirname(@filename) if @filename
      
      # If directory is given w/o filename, pick a random manifest location
      if @directory && @filename.nil?
        @filename = File.join(@directory, 'manifest.json')
      end
      
      unless @directory && @filename
        raise ArgumentError, "manifest requires output filename"
      end
      
      if File.exist?(@filename)
        begin
          @data = JSON.parse(File.read(@filename))
        rescue JSON::ParserError => e
          @data = {}
          # logger.error "#{@filename} is invalid: #{e.class} #{e.message}"
          puts "#{@filename} is invalid: #{e.class} #{e.message}"
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
      asset.export
      
      @data[asset.filename] = asset.to_json
      
      outputs = asset.write(@directory)
      asset.linked_assets.each { |a| outputs += add_asset(a) }
      outputs
    end
    
    def compile(*args)
      reset
      outputs = add(*args)
      save
      outputs
    end
    
    # Persist manfiest back to FS
    def save
      return if @filename.nil?
      FileUtils.mkdir_p File.dirname(@filename)
      Utils.atomic_write(@filename) { |f| f.write(JSON.generate(@data)) }
    end
    
  end
end