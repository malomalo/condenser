# frozen_string_literal: true

require 'json'
require 'fileutils'

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
          @data = JSON.parse(File.read(@filename), symbolize_names: true).transform_keys(&:to_s)
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
        outputs += add_asset(la)
      end
      outputs
    end
    
    def [](key)
      add(key) if @environment
      @data[key.delete_prefix('/')]
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
    
    # Remove files in the output directory that aren't in the manifest, then
    # any directories left empty.
    def clean
      return if !Dir.exist?(dir)

      # Manifest paths are relative to the output directory; keep each one
      # and its compressed versions.
      keep = @data.values.flat_map { |v| [v[:path], v[:sourcemap]].compact }
      keep = keep.flat_map { |path| [path, "#{path}.gz", "#{path}.br"] }.to_set
      clean_dir(dir, keep)
      nil
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

    private

    # Remove files in +dir+ that aren't in +keep+, then any directories left
    # empty. Never removes the manifest. Returns true if +dir+ is now empty.
    def clean_dir(dir, keep, prefix = nil)
      empty = true
      Dir.each_child(dir) do |child|
        relative_path = prefix ? File.join(prefix, child) : child
        child = File.join(dir, child)
        stat = File.lstat(child)

        # Don't follow symlinks out of the output directory
        if stat.directory?
          if clean_dir(child, keep, relative_path)
            Dir.rmdir(child)
            logger.info "Removed #{child}"
            next
          end
        elsif stat.file? && child != filename && !keep.include?(relative_path)
          File.delete(child)
          logger.info "Removed #{child}"
          next
        end
        empty = false
      end
      empty
    end

  end
end