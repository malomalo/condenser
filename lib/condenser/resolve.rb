class Condenser
  module Resolve
    
    def initialize(root)
      @reverse_mapping = nil
    end
    
    def resolve(filename, accept: nil, ignore: [])
      dirname, basename, extensions, mime_types = decompose_path(filename)
      results = []
      
      accept ||= mime_types.empty? ? ['*/*'] : mime_types
      accept = Array(accept)

      path.each do |path|
        glob = path
        glob = File.join(glob, dirname) if dirname
        glob = File.join(glob, basename)
        glob << '.*' unless glob.end_with?('*')
        
        Dir.glob(glob).sort.each do |f|
          next if !File.file?(f) || ignore.include?(f)
          
          f_dirname, f_basename, f_extensions, f_mime_types = decompose_path(f)
          if (basename == '*' || basename == f_basename)
            if accept == ['*/*'] || mime_type_match_accept?(f_mime_types, accept)
              asset_dir = f_dirname.delete_prefix(path).delete_prefix('/')
              asset_basename = f_basename + f_extensions.join('')
              asset_filename = asset_dir.empty? ? asset_basename : File.join(asset_dir, asset_basename)
              results << Asset.new(self, {
                filename: asset_filename,
                content_types: f_mime_types,
                source_file: f
              })
            end
            
            reverse_mapping[f_mime_types]&.each do |derivative_mime_types|
              if accept == ['*/*'] || mime_type_match_accept?(derivative_mime_types, accept)
                asset_dir = f_dirname.delete_prefix(path).delete_prefix('/')
                asset_basename = f_basename + derivative_mime_types.map { |t| @mime_types[t][:extensions].first }.join('')
                asset_filename = asset_dir.empty? ? asset_basename : File.join(asset_dir, asset_basename)
                results << Asset.new(self, {
                  filename: asset_filename,
                  content_types: derivative_mime_types,
                  source_file: f
                })
              end
            end
          end
        end
      end

      results.sort_by! do |a|
        accept.find_index { |m| match_mime_types?(a.content_types, m) }
      end
      results = results.map { |a| a.filename.sub(/\.(\w+)$/, '') }.uniq.map {|fn| results.find {|r| r.filename.sub(/\.(\w+)$/, '') == fn}}
      results
    end

    def resolve!(filename, **kargs)
      assets = resolve(filename, **kargs)
      if assets.empty?
        raise FileNotFound, "couldn't find file '#{filename}'"
      else
        assets
      end
    end

    def find(filename, **kargs)
      resolve(filename, **kargs).first
    end
    
    def find!(filename, **kargs)
      resolve!(filename, **kargs).first
    end
    
    def [](*args)
      find!(*args)
    end
    
    def find_export(filename, **kargs)
      asset = resolve(filename, **kargs).first
      asset&.export
      asset
    end

    
    def decompose_path(path)
      dirname = path.index('/') ? File.dirname(path) : nil
      _, basename, extensions = path.match(/([^\.\/]+)(\.[^\/]*)?$/).to_a
      
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
            raise 'unkown mime'
          else
            matching_extensions.sort_by! { |e| -e.length }
            exts.unshift(matching_extensions.first)
            extensions.delete_suffix!(matching_extensions.first)
          end
        end
        extensions = exts
        mime_types = extensions.map { |k| @extensions[k] }
      end
      
      
      [ dirname == '.' ? nil : dirname, basename, extensions, mime_types ]
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
      value.length == matcher.length && value.zip(matcher).all? { |v, m| match_mime_type?(v, m) }
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


