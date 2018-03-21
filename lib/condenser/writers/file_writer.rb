require 'condenser/utils'

class Condenser
  # Writes a an asset file to disk
  class FileWriter

    def skip?(asset, logger)
      if ::File.exist?(asset.path)
        logger.debug "Skipping #{ asset.filename }, already exists"
        true
      else
        logger.info "Writing #{ asset.filename }"
        false
      end
    end

    def call(output_directory, asset)
      filename = File.join(output_directory, asset.path)
      FileUtils.mkdir_p(File.dirname(filename))
      Utils.atomic_write(filename) do |file|
        file.write(asset.source)
      end
      
      [asset.filename]
    end
    
  end
end