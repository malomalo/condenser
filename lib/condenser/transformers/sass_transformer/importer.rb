require 'sass/importers'

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