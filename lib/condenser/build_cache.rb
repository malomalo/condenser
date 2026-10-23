# frozen_string_literal: true

class Condenser
  class BuildCache
    
    attr_reader :semaphore, :listening, :logger

    # Files that change when npm packages are installed or updated.
    # node_modules/.package-lock.json is rewritten by every `npm install`.
    NPM_LOCKFILES = %w(
      node_modules/.package-lock.json
      package-lock.json
      yarn.lock
      pnpm-lock.yaml
      bun.lock
      bun.lockb
    ).freeze

    # Ignored under every watched path, on top of Listen's defaults.
    WATCH_IGNORES = [%r{(?:\A|/)node_modules(?:/|\z)}, %r{\A(?:\.git|tmp|log)(?:/|\z)}].freeze

    # rb-inotify watches a new directory only after Listen has scanned it, so
    # a file written in between is never reported. Watching it before the
    # scan means the scan or an event catches every file.
    module WatchNewDirectoriesFirst
      private

      def _process_event(dir, event)
        if _dir_event?(event) && (event.flags & [:create, :moved_to]).any? && @callbacks&.key?(dir)
          begin
            @worker.watch(event.absolute_name, *options.events, &@callbacks[dir])
          rescue SystemCallError
          end
        end
        super
      end
    end

    def initialize(path, logger:, listen: {})
      @logger = logger
      @path = path
      @map_cache = {}
      @lookup_cache = {}
      @process_dependencies = {}
      @export_dependencies = {}
      @file_dependencies = {}
      @directory_dependencies = {}
      @bare_file_dependencies = {}
      @bare_directory_dependencies = {}
      @recorded_file_dependencies = {}.compare_by_identity
      @file_digests = {}
      @directory_digests = {}
      @build_file_digests = nil
      @watch_listeners = []
      @watched_paths = []
      @listening = if listen
        require 'listen'
        Listen::Adapter::Linux.prepend(WatchNewDirectoriesFirst)
        Listen::Adapter.select != Listen::Adapter::Polling
      else
        false
      end
      
      if !@listening
        @polling = false
      else
        @semaphore = Mutex.new
        @on_change = lambda do |modified, added, removed|
          modified = Set.new(modified)
          added = Set.new(added)
          removed = Set.new(removed)
          
          @semaphore.synchronize do
            @logger.debug { "build cache semaphore locked by #{Thread.current.object_id}" }
            @logger.debug do
              (
                removed.map { |f| "Asset removed: #{f}" } +
                added.map { |f| "Asset created: #{f}" } +
                modified.map { |f| "Asset updated: #{f}" }
              ).join("\n")
            end

            globs = Set.new
            dirs = Set.new
            (added + removed + modified).each do |file|
              globs << file.match(/([^\.]+)(\.|$)/).to_a[1]
              @path.select { |p| file.start_with?(File.join(p, '')) }.each do |path_match|
                a = file.delete_prefix(path_match).match(/([^\.]+)(\.|$)/).to_a[1]
                b = File.join(File.dirname(a), "*")
              
                globs << a << a.delete_prefix('/')
                globs << b << b.delete_prefix('/')

                # Adding or removing a file, which may be in a new directory,
                # changes the recursive globs of every directory above it
                if !modified.include?(file)
                  dir = File.dirname(a)
                  until dir == (dir = File.dirname(dir))
                    break unless dirs.add?(dir)
                    c = File.join(dir, '**')
                    globs << c << c.delete_prefix('/')
                  end
                end
              end
            end

            others = []
            @map_cache&.delete_if do |k,v|
              if globs.any?{ |a| k.starts_with?(a) }
                dependents(@export_dependencies, v.source_file).each do |a|
                  others << "/#{a.filename}".delete_suffix(File.extname(a.filename))
                end
                true
              else
                false
              end
            end
            @map_cache&.delete_if do |k,v|
              others.any?{ |a| k.starts_with?(a) || k.starts_with?("/" + a) }
            end
            
            others = []
            @lookup_cache.delete_if do |key, value|
              if globs.any?{ |a| key.starts_with?(a) }
                value.each do |v|
                  dependents(@export_dependencies, v.source_file).each do |a|
                    others << "/#{a.filename}".delete_suffix(File.extname(a.filename))
                  end
                end
                value.each do |asset|
                  modified << asset.source_file
                end
                true
              end
            end
            @lookup_cache&.delete_if do |k,v|
              others.any?{ |a| k.starts_with?(a) || k.starts_with?("/" + a) }
            end

            (added + removed + modified).each do |file|
              @file_dependencies[file]&.each { |asset| modified << asset.source_file }
              dir = File.dirname(file)
              loop do
                @directory_dependencies[dir]&.each { |asset| modified << asset.source_file }
                break if dir == (dir = File.dirname(dir))
              end

              @path.each do |load_path|
                prefix = File.join(self.class.real_path(load_path), '')
                next if !file.start_with?(prefix)

                name = file.delete_prefix(prefix)
                @bare_file_dependencies[name]&.each { |asset| modified << asset.source_file }
                until (name = File.dirname(name)) == '.'
                  @bare_directory_dependencies[name]&.each { |asset| modified << asset.source_file }
                end
              end
            end
            
            removed.each do |file|
              dependents(@process_dependencies, file).each do |asset|
                asset.needs_reprocessing! if asset.source_file != file
              end
              dependents(@export_dependencies, file).each do |asset|
                asset.needs_reexporting! if asset.source_file != file
              end
              @process_dependencies[file]&.delete_if { |asset| asset.source_file == file }
              @export_dependencies[file]&.delete_if { |asset| asset.source_file == file }
            end
            
            modified.each do |file|
              dependents(@process_dependencies, file).each(&:needs_reprocessing!)
              dependents(@export_dependencies, file).each(&:needs_reexporting!)
            end

            @logger.debug { "build cache semaphore unlocked by #{Thread.current.object_id}" }
          end
        end
        @listened_paths = path.map { |p| self.class.real_path(p) }
        @listener = Listen.to(*path, &@on_change)
        @listener.start
      end
    end

    # Listens for changes under +path+, which isn't on the load path, so the
    # file dependencies there invalidate the assets that depend on them.
    # +ignore+ is a list of Regexps matched against the paths relative to
    # +path+, or Strings that are directories (or files) relative to it. A
    # path already listened to, as or under a load path or a watched path, is
    # skipped, and the ones under +path+ are ignored.
    def watch(path, ignore: [])
      return if !@listening

      path = self.class.real_path(path)
      return if @listened_paths.any? { |root| self.class.covers?(root, path) }
      return if @watched_paths.any? { |root, ignores| self.class.covers?(root, path, ignore: ignores) }

      prefix = File.join(path, '')
      ignore = Array(ignore) + (@listened_paths + @watched_paths.map(&:first))
        .select { |p| p.start_with?(prefix) }
        .map { |p| p.delete_prefix(prefix) }
      listener = Listen.to(path, ignore: self.class.watch_ignores(ignore), &@on_change)
      listener.start
      @watch_listeners << listener
      @watched_paths << [path, ignore]
    end

    # The Regexps Listen ignores under a watched path for +ignore+.
    def self.watch_ignores(ignore)
      WATCH_IGNORES + Array(ignore).map do |i|
        i.is_a?(Regexp) ? i : %r{\A#{Regexp.escape(i.delete_suffix('/'))}(?:/|\z)}
      end
    end

    # Whether a listener on +root+ that ignores +ignore+ hears about the
    # directory +path+, both real paths.
    def self.covers?(root, path, ignore: nil)
      return true if path == root
      return false if !path.start_with?(File.join(root, ''))
      return true if ignore.nil?

      relative = path.delete_prefix(File.join(root, ''))
      watch_ignores(ignore).none? { |i| i.match?(relative) }
    end
    
    def map(key)
      @map_cache[key] ||= yield
    end
    
    def []=(value, assets)
      @lookup_cache[value] = assets
    end
    
    # Record the direct dependencies of an asset so the listener can find
    # everything that needs to be rebuilt when a file changes. Only direct
    # edges are stored; the transitive set is computed in #dependents when a
    # file actually changes.
    def record_process_dependencies(asset, deps)
      record_dependencies(@process_dependencies, asset, deps)
    end
    
    def record_export_dependencies(asset, deps)
      record_dependencies(@export_dependencies, asset, deps)
    end

    # +files+ and +directories+ are [name, path] pairs, with a nil path if
    # it's missing. A bare name is also indexed by name, so a file added or
    # removed in another load path that changes where it resolves invalidates
    # the asset.
    #
    # Recording the same ones for the asset again in a build is skipped,
    # since the indexes are only added to.
    def record_file_dependencies(asset, files, directories)
      return if !@listening
      return if @recorded_file_dependencies[asset] == [files, directories]

      @recorded_file_dependencies[asset] = [files, directories]
      [[files, @file_dependencies, @bare_file_dependencies], [directories, @directory_dependencies, @bare_directory_dependencies]].each do |deps, index, bare_index|
        deps.each do |name, path|
          absolute = File.absolute_path?(name)
          path ||= name if absolute
          (index[self.class.real_path(path)] ||= Set.new) << asset if path
          (bare_index[name] ||= Set.new) << asset if !absolute
        end
      end
    end

    # Listen reports paths with symlinks resolved, e.g. /private/var for
    # /var on macOS or a Capistrano release for its `current` symlink.
    # A missing path resolves through its nearest existing parent.
    def self.real_path(path)
      File.realpath(path)
    rescue Errno::ENOENT, Errno::ENOTDIR
      parent = File.dirname(path)
      return path if parent == path

      File.join(real_path(parent), File.basename(path))
    end

    # A digest of the file's contents, or nil if it's missing. It's only
    # recomputed when the file's stat changes, and during a build it's only
    # checked once.
    def file_digest(path)
      return @build_file_digests[path] if @build_file_digests&.key?(path)

      digest = begin
        stat = File.stat(path)
        if stat.file?
          signature = [stat.mtime.to_r, stat.ctime.to_r, stat.size, stat.ino]
          cached = @file_digests[path]
          if cached && cached[0] == signature
            cached[1]
          else
            (@file_digests[path] = [signature, Digest::SHA256.file(path).base64digest])[1]
          end
        end
      rescue Errno::ENOENT, Errno::ENOTDIR
        @file_digests.delete(path)
        nil
      end
      @build_file_digests[path] = digest if @build_file_digests
      digest
    end

    # A digest of the names of the files in +path+ that match +globs+ and of
    # its subdirectories (and, if +recursive+, the same for each
    # subdirectory), or nil if it's missing. Adding, removing or renaming a
    # matching file or a subdirectory changes it. It's only recomputed when
    # the mtime of a directory it lists changes.
    def directory_digest(path, globs: ['*'], recursive: false)
      key = [path, globs, recursive]
      cached = @directory_digests[key]
      if cached && cached[0].all? { |dir, mtime| (File.stat(dir).mtime.to_r rescue nil) == mtime }
        return cached[1]
      end

      mtimes = []
      names = []
      return if !list_directory(path, '', globs, recursive, mtimes, names)

      (@directory_digests[key] = [mtimes, Digest::SHA256.base64digest(names.join("\0"))])[1]
    end
    
    # Returns the assets that depend on +source_file+, either directly or
    # through other assets, including the assets built from +source_file+.
    def dependents(index, source_file)
      found = Set.new
      queue = [source_file]
      seen = Set.new
      while file = queue.shift
        next unless seen.add?(file)
        index[file]&.each do |asset|
          queue << asset.source_file if found.add?(asset)
        end
      end
      found
    end
    
    # Called when a build starts, before anything is built.
    def start_build
      @recorded_file_dependencies.clear
      @build_file_digests = {}
    end

    # Called when a build has finished.
    def finish_build
      @build_file_digests = nil
    end

    # node_modules isn't watched by the listener, so clear everything when
    # the npm packages change (e.g. after an `npm install`) instead.
    def clear_if_npm_changed(npm_path)
      return if npm_path.nil?

      fingerprint = NPM_LOCKFILES.filter_map do |lockfile|
        stat = File.stat(File.join(npm_path, lockfile))
        [lockfile, stat.mtime.to_f, stat.size]
      rescue Errno::ENOENT
        nil
      end

      if @npm_fingerprint && @npm_fingerprint != fingerprint
        @logger.info { "npm packages changed, clearing the build cache" }
        clear
      end
      @npm_fingerprint = fingerprint
    end

    def clear
      @map_cache.clear
      @lookup_cache.clear
      @process_dependencies.clear
      @export_dependencies.clear
      @file_dependencies.clear
      @directory_dependencies.clear
      @bare_file_dependencies.clear
      @bare_directory_dependencies.clear
      @recorded_file_dependencies.clear
      @npm_packages = nil
      @npm_digests = nil
    end

    # The packages in npm's lockfile, keyed by where they're installed
    # (e.g. "node_modules/komps" or "node_modules/a/node_modules/b").
    # node_modules/.package-lock.json describes what's actually installed, so
    # it's preferred over package-lock.json.
    def npm_packages(npm_path)
      return {} if npm_path.nil?

      @npm_packages ||= begin
        lockfile = %w(node_modules/.package-lock.json package-lock.json)
          .map { |f| File.join(npm_path, f) }
          .find { |f| File.file?(f) }
        lockfile ? (JSON.parse(File.read(lockfile))['packages'] || {}) : {}
      end
    end

    # The lockfile key of the package +name+ as node would find it from the
    # package installed at +from+ ("" for the app itself), or nil.
    def resolve_npm_package(npm_path, from, name)
      packages = npm_packages(npm_path)
      dir = from
      loop do
        key = dir.empty? ? "node_modules/#{name}" : "#{dir}/node_modules/#{name}"
        return key if packages.key?(key)
        return if dir.empty?
        dir = dir.sub(%r{/?node_modules/(?:@[^/]+/)?[^/]+\z}, '')
      end
    end

    # A digest of the lockfile entries for the packages +keys+ and everything
    # they depend on, or nil if +keys+ is empty or there's no lockfile. A
    # package's entry changes when it's upgraded (its version, or for git
    # dependencies the commit in `resolved`).
    def npm_packages_digest(npm_path, keys)
      return if keys.empty?

      packages = npm_packages(npm_path)
      return if packages.empty?

      @npm_digests ||= {}
      @npm_digests[keys.sort] ||= begin
        seen = Set.new
        queue = keys.to_a
        while key = queue.shift
          next if !seen.add?(key)

          %w(dependencies peerDependencies optionalDependencies).each do |field|
            packages.dig(key, field)&.each_key do |name|
              dep = resolve_npm_package(npm_path, key, name)
              queue << dep if dep
            end
          end
        end

        Digest::SHA256.hexdigest(JSON.generate(seen.sort.map { |key|
          [key, packages[key]&.slice('version', 'resolved', 'integrity')]
        }))
      end
    end

    def clear_lookups
      @lookup_cache.clear
    end
    
    def [](value)
      @lookup_cache[value]
    end
    
    def fetch(key)
      value = self[key]
      
      if value.nil?
        value = yield
        # Lookups that find nothing are only cached while listening, since
        # the listener is what clears them when a matching file is added.
        if @listening || (value.is_a?(Array) ? !value.empty? : value)
          self[key] = value
        end
      end
      
      value
    end
    
    private

    def list_directory(dir, prefix, globs, recursive, mtimes, names)
      mtimes << [dir, File.stat(dir).mtime.to_r]
      Dir.children(dir).sort.each do |name|
        full = File.join(dir, name)
        if File.lstat(full).directory?
          next if name.start_with?('.')
          names << "#{prefix}#{name}/"
          list_directory(full, "#{prefix}#{name}/", globs, recursive, mtimes, names) if recursive
        elsif globs.any? { |g| File.fnmatch?(g, name, File::FNM_EXTGLOB) }
          names << "#{prefix}#{name}"
        end
      end
      true
    rescue Errno::ENOENT, Errno::ENOTDIR
      false
    end
    
    def record_dependencies(index, asset, deps)
      return if !@listening

      # An asset always depends on its own source file
      (@process_dependencies[asset.source_file] ||= Set.new) << asset
      (@export_dependencies[asset.source_file] ||= Set.new) << asset
      deps.each do |dep|
        (index[dep.source_file] ||= Set.new) << asset
      end
    end
    
  end
end