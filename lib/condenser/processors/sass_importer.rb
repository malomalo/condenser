require 'sass/importers'

class Condenser
  class SassImporter < Sass::Importers::Filesystem
    module Globbing
      GLOB = /(\A|\/)(\*|\*\*\/\*)\z/

      def find_relative(name, base, options)
        if options[:condenser] && m = name.match(GLOB)
          path = name.sub(m[0], "")
          base = File.expand_path(path, File.dirname(base)).delete_prefix(File.expand_path('.') + '/')
          glob_imports(base, m[2], options)
        else
          super
        end
      end

      def find(name, options)
        # globs must be relative
        return if name =~ GLOB
        super
      end

      private
        def glob_imports(base, glob, options)
          contents = ""
          each_globbed_file(base, glob, options) do |asset|
            next if asset.filename == options[:filename]
            contents << "@import #{asset.filename.inspect};\n"
          end
          return nil if contents == ""
          Sass::Engine.new(contents, options.merge(
            filename: base,
            importer: self,
            syntax: :scss
          ))
        end

        def each_globbed_file(base, glob, options)
          raise ArgumentError unless glob == "*" || glob == "**/*"

          exts = extensions.keys.map { |ext| Regexp.escape(".#{ext}") }.join("|")
          sass_re = Regexp.compile("(#{exts})$")

          # context.depend_on(base) Here we need to watch all dirs
          # if File.directory?(path)
            # context.depend_on(path)
            
          env = options[:condenser][:environment]
          env.resolve("#{base}/#{glob}", accept: [['text/sass'], ['text/scss'], ['text/css']]).sort_by(&:filename).each do |asset|
            if sass_re =~ asset.filename
              yield asset
            end
          end
        end
    end

    include Globbing

    # Allow .css files to be @import'd
    def extensions
      { 'css' => :scss }.merge(super)
    end
  end
end