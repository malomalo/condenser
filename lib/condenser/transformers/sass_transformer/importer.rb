class Condenser::SassTransformer
  class Importer < SassC::Importer
    
    def imports(name, base)
      name = expand_path(name, base)
      env = options[:condenser][:environment]
      accept = extensions.keys.map { |x| options[:condenser][:environment].extensions[x] }

      options[:asset][:dependencies] << [name, accept.map{ |i| [i] }]

      imports = []
      env.resolve(name, accept: accept).sort_by(&:filename).each do |asset|
        next if asset.filename == options[:filename]
        imports << Import.new(asset.filename, source: asset.source, source_map_path: nil)
      end

      if imports.empty? && env.npm_path
        package = File.join(env.npm_path, name, 'package.json')
        if File.exists?(package)
          package = JSON.parse(File.read(package))
          if package['style']
            imports << Import.new(name, source: File.read(File.join(env.npm_path, name, package['style'])), source_map_path: nil)
          end
        end
      end

      raise Condenser::FileNotFound, "couldn't find file '#{name}'" if imports.empty?

      imports
    end
    
    # Allow .css files to be @imported
    def extensions
      { '.sass' => :sass, '.scss' => :scss, '.css' => :scss }
    end
    
    private

      def expand_path(path, base=nil)
        if path.start_with?('.')
          File.expand_path(path, File.dirname(base)).delete_prefix(File.expand_path('.') + '/')
        else
          File.expand_path(path).delete_prefix(File.expand_path('.') + '/')
        end
      end
        
  end
end