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
      record_build
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
    
    # Remove files in the output directory that aren't in the current manifest
    # or one of the last +keep+ builds recorded by #compile, and the records of
    # older builds. Does nothing until +keep+ builds have been recorded.
    def clean(keep: 2)
      if !keep.is_a?(Integer) || keep < 1
        raise ArgumentError, "keep must be an Integer >= 1, got #{keep.inspect}"
      end
      return if !Dir.exist?(dir)

      builds = recorded_builds
      if builds.size < keep
        logger.info "Not cleaning #{dir}: #{builds.size} of #{keep} builds recorded"
        return
      end

      # Manifest paths are relative to the output directory; keep each one
      # and its compressed versions.
      entries = @data.values + builds.last(keep).flat_map { |b| read_build(b).values }
      paths = entries.flat_map { |v| [v[:path], v[:sourcemap]].compact }
      paths = paths.flat_map { |path| [path, "#{path}.gz", "#{path}.br"] }.to_set
      clean_dir(dir, paths)

      builds[0...-keep].each do |build|
        File.delete(build)
        logger.info "Removed #{build}"
      end
      nil
    end

    # Wipe directive
    def clobber
      return if !Dir.exist?(dir)
      
      FileUtils.rm(filename)
      logger.info "Removed #{filename}"

      if Dir.exist?(history_dir)
        FileUtils.rm_r(history_dir)
        logger.info "Removed #{history_dir}"
      end
      
      Dir.each_child(dir) do |child|
        FileUtils.rm_r(File.join(dir, child))
      end
      
      logger.info "Removed contents of #{dir}"
      nil
    end

    private

    # Where #compile records each build, next to the manifest file.
    def history_dir
      File.join(File.dirname(filename), ".#{File.basename(filename, '.*')}-builds")
    end

    # Recorded builds, oldest first.
    def recorded_builds
      return [] if !Dir.exist?(history_dir)
      Dir.children(history_dir).select { |f| f.end_with?('.json') }.sort.map { |f| File.join(history_dir, f) }
    end

    def read_build(build)
      JSON.parse(File.read(build), symbolize_names: true)
    end

    # Write a copy of the manifest data to the history directory, unless it's
    # the same as the latest build's. Names are UTC timestamps with
    # nanoseconds, so they sort chronologically.
    def record_build
      data = JSON.parse(JSON.generate(@data), symbolize_names: true)
      latest = recorded_builds.last
      return if latest && read_build(latest) == data

      time = Time.now.utc
      loop do
        name = "#{time.strftime('%Y%m%d%H%M%S%9N')}.json"
        if latest.nil? || name > File.basename(latest)
          FileUtils.mkdir_p(history_dir)
          Utils.atomic_write(File.join(history_dir, name)) { |f| f.write(JSON.generate(@data)) }
          return
        end
        # Same or earlier time than the latest build's name
        time += Rational(1, 1_000_000_000)
      end
    end

    # Remove files in +dir+ that aren't in +keep+, then any directories left
    # empty. Never removes the manifest or the history directory. Returns true
    # if +dir+ is now empty.
    def clean_dir(dir, keep, prefix = nil)
      empty = true
      Dir.each_child(dir) do |child|
        relative_path = prefix ? File.join(prefix, child) : child
        child = File.join(dir, child)
        stat = File.lstat(child)

        # Don't follow symlinks out of the output directory
        if stat.directory? && child != history_dir
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