# frozen_string_literal: true

require 'json'
require 'fileutils'

class Condenser
  class Manifest
    
    attr_reader :filename, :dir, :environment
    
    def initialize(environment = nil, dir:, filename: nil, logger: nil)
      if environment && !environment.is_a?(Condenser)
        raise ArgumentError, "environment must be a Condenser, got #{environment.class}"
      end
      raise ArgumentError, "manifest requires a dir" if dir.nil?

      @environment = environment
      @logger = logger || (environment ? nil : Logger.new($stdout, level: :info))
      @dir = File.expand_path(dir)
      @filename = File.expand_path(filename || File.join(@dir, 'manifest.json'))
      
      if File.exist?(@filename)
        begin
          @data = JSON.parse(File.read(@filename), symbolize_names: true).transform_keys(&:to_s)
        rescue JSON::ParserError => e
          @data = {}
          self.logger.error "#{@filename} is invalid: #{e.class} #{e.message}"
        end
      else
        @data = {}
      end
    end
    
    def logger
      @logger || @environment.logger
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
      outputs
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
      # and the files the writers name after it (e.g. "#{path}.gz").
      keep = @data.values.flat_map { |v| [v[:path], v[:sourcemap]].compact }.to_set
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
        elsif stat.file? && child != filename && !kept?(relative_path, keep)
          File.delete(child)
          logger.info "Removed #{child}"
          next
        end
        empty = false
      end
      empty
    end

    # Whether +path+ is in +keep+ or is a kept path with extra extensions.
    # File.extname only looks at the basename, so this never strips into a
    # directory name, and a dotfile like ".gz" has no extension.
    def kept?(path, keep)
      while !keep.include?(path)
        ext = File.extname(path)
        return false if ext.empty?
        path = path.delete_suffix(ext)
      end
      true
    end

  end
end