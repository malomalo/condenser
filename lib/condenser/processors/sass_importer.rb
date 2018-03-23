require 'sass/importers'

class Condenser
  class SassImporter < Sass::Importers::Base

    GLOB = /(\A|\/)(\*|\*\*\/\*)\z/

    def initialize(env)
      @environment = env
    end
      
    def key(name, options)
      [self.class.name + ':' + File.dirname(expand_path(name)), File.basename(name)]
    end
      
    def public_url(name, sourcemap_directory)
      Sass::Util.file_uri_from_path(name)
    end
      
    def find_relative(name, base, options)
      name = expand_path(name, base)
      puts "find_relative(#{[name, base].map(&:inspect).join(', ')}, options)"
      env = options[:condenser][:environment]
      accept = extensions.keys.map { |x| options[:condenser][:environment].extensions[x] }
      

      if name.match(GLOB)
        contents = ""
        env.resolve(name, accept: accept).sort_by(&:filename).each do |asset|
          next if asset.filename == options[:filename]
          contents << "@import \"#{asset.filename}\";\n"
        end
        
        return nil if contents == ""
        Sass::Engine.new(contents, options.merge(
          filename: name,
          importer: self,
          syntax: :scss
        ))
      else
        asset = options[:condenser][:environment].find(name, accept: accept)

        if asset
          asset.process
          Sass::Engine.new(asset.source, options.merge(
            filename: asset.filename,
            importer: self,
            syntax: extensions[asset.ext]
          ))
        else
          nil
        end
      end
    end

    def find(name, options)
      puts "find(#{name.inspect}, options)"
      if options[:condenser]
        puts name, '-'*80
        # globs must be relative
        return if name =~ GLOB
        super
      else
        super
      end
    end

    # Allow .css files to be @import'd
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