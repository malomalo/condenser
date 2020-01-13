class Condenser
  module Resolve
    
    def initialize(*args, **kws, &block)
      @reverse_mapping = nil
      @build_cache_options = kws[:listen]
      super
    end
    
    def build_cache
      return @build_cache if instance_variable_defined?(:@build_cache)
      @build_cache = BuildCache.new(path)
    end
    
    def resolve(filename, base=nil, accept: nil)
      filename = filename.delete_prefix("/") if path.none? { |p| filename.start_with?(p) }
      dirname, basename, extensions, mime_types = decompose_path(filename, base)
      accept ||= mime_types.empty? ? ['*/*'] : mime_types
      accept = Array(accept)
      
      cache_key = [dirname, basename].flatten.join('/')
      cache_key << "@#{accept.join(',')}" if accept
      
      build_cache.fetch(cache_key) do
        build do
          results = []

          paths = if dirname&.start_with?('/')
            if pat = path.find { |pa| dirname.start_with?(pa) }
              dirname.delete_prefix!(pat)
              dirname.delete_prefix!('/')
              [pat]
            else
              []
            end
          else
            path
          end
        
          paths.each do |path|
            glob = path
            glob = File.join(glob, dirname) if dirname
            glob = File.join(glob, basename)
            glob << '.*' unless glob.end_with?('*')
          
            Dir.glob(glob).sort.each do |f|
              next if !File.file?(f)
          
              f_dirname, f_basename, f_extensions, f_mime_types = decompose_path(f)
              if (basename == '*' || basename == f_basename)
                if accept == ['*/*'] || mime_type_match_accept?(f_mime_types, accept)
                  asset_dir = f_dirname.delete_prefix(path).delete_prefix('/')
                  asset_basename = f_basename + f_extensions.join('')
                  asset_filename = asset_dir.empty? ? asset_basename : File.join(asset_dir, asset_basename)
                  results << build_cache.map(asset_filename + f_mime_types.join('')) do
                    Asset.new(self, {
                      filename: asset_filename,
                      content_types: f_mime_types,
                      source_file: f,
                      source_path: path
                    })
                  end
                else
                  reverse_mapping[f_mime_types]&.each do |derivative_mime_types|
                    if accept == ['*/*'] || mime_type_match_accept?(derivative_mime_types, accept)
                      asset_dir = f_dirname.delete_prefix(path).delete_prefix('/')
                      asset_basename = f_basename + derivative_mime_types.map { |t| @mime_types[t][:extensions].first }.join('')
                      asset_filename = asset_dir.empty? ? asset_basename : File.join(asset_dir, asset_basename)
                      results << build_cache.map(asset_filename + derivative_mime_types.join('')) do
                        Asset.new(self, {
                          filename: asset_filename,
                          content_types: derivative_mime_types,
                          source_file: f,
                          source_path: path
                        })
                      end
                    end
                  end
                end

              end
            end
          end
        
          results = results.group_by do |a|
            accept.find_index { |m| match_mime_types?(a.content_types, m) }
          end
        
          results = results.keys.sort.reduce([]) do |c, key|
            c += results[key].sort_by(&:filename)
          end

          results.sort_by!(&:filename)
          results
        end
      end
    end

    def resolve!(filename, base=nil, **kargs)
      build do
        assets = resolve(filename, base, **kargs)
        if assets.empty?
          raise FileNotFound, "couldn't find file '#{filename}'"
        else
          assets
        end
      end
    end

    def find(filename, base=nil, accept: nil)
      build do
        resolve(filename, base, accept: accept).first
      end
    end
    
    def find!(filename, base=nil, **kargs)
      build do
        resolve!(filename, base, **kargs).first
      end
    end
    
    def [](filename)
      build do
        find!(filename).export
      end
    end
    
    def find_export(filename, base=nil, **kargs)
      build do
        asset = resolve(filename, base, **kargs).first
        asset&.export
      end
    end
    
    def build
      @build_cc += 1
      if @build_cc == 1
        build_cache.semaphore.lock if build_cache.listening
      end
      yield
    ensure
      @build_cc -= 1
      if @build_cc == 0
        build_cache.semaphore.unlock if build_cache.listening
      end
    end
    
    def decompose_path(path, base=nil)
      dirname = path.index('/') ? File.dirname(path) : nil
      if base && path&.start_with?('.')
        dirname = File.expand_path(dirname, base)
      end
      
      _, star, basename, extensions = path.match(/(([^\.\/]+)(\.[^\/]+)|\*|[^\/]+)$/).to_a
      if extensions == '.*'
        extensions = nil
      end
      if basename.nil? && extensions.nil?
        basename = star
      end
        
      if extensions.nil? && basename == '*'
        extensions = nil
        mime_types = []
      elsif extensions.nil?
        mime_types = []
      else
        exts = []
        while !extensions.empty?
          matching_extensions = @extensions.keys.select { |e| extensions.end_with?(e) }
          if matching_extensions.empty?
            basename << extensions
            break
            # raise 'unkown mime'
          else
            matching_extensions.sort_by! { |e| -e.length }
            exts.unshift(matching_extensions.first)
            extensions.delete_suffix!(matching_extensions.first)
          end
        end
        extensions = exts
        mime_types = extensions.map { |k| @extensions[k] }
      end
      
      
      [ dirname, basename, extensions, mime_types ]
    end
    
    def reverse_mapping
      return @reverse_mapping if @reverse_mapping
      map = {}
      @mime_types.each_key do |source_mime_type|
        to_mime_type = source_mime_type

        ([nil] + (@transformers[source_mime_type]&.keys || [])).each do |transform_mime_type|
          to_mime_type = transform_mime_type if transform_mime_type
          
          ([nil] + @templates.keys).each do |template_mime_type|
            from_mimes = [source_mime_type, template_mime_type].compact
            to_mime_types = [to_mime_type].compact
            if from_mimes != to_mime_types
              map[from_mimes] ||= Set.new
              map[from_mimes] << to_mime_types
            end
          end

        end
      end
      $map = map
    end

    def writers_for_mime_type(mime_type)
      @writers.select { |m, e| match_mime_type?(mime_type, m) }.values.reduce(&:+)
    end
    
    def match_mime_types?(value, matcher)
      matcher = Array(matcher)
      value = Array(value)
      
      if matcher.length == 1 && matcher.last == '*/*'
        true
      else
        value.length == matcher.length && value.zip(matcher).all? { |v, m| match_mime_type?(v, m) }
      end
    end
    
    def mime_type_match_accept?(value, accept)
      accept.any? do |a|
        match_mime_types?(value, Array(a))
      end
    end
        
    # Public: Test mime type against mime range.
    #
    #    match_mime_type?('text/html', 'text/*') => true
    #    match_mime_type?('text/plain', '*') => true
    #    match_mime_type?('text/html', 'application/json') => false
    #
    # Returns true if the given value is a mime match for the given mime match
    # specification, false otherwise.
    def match_mime_type?(value, matcher)
      v1, v2 = value.split('/'.freeze, 2)
      m1, m2 = matcher.split('/'.freeze, 2)
      (m1 == '*'.freeze || v1 == m1) && (m2.nil? || m2 == '*'.freeze || m2 == v2)
    end
    
  end
end


