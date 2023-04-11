# Public: Functions injected into Sass context during Condenser evaluation.
#
# This module may be extended to add global functionality to all Condenser
# Sass environments. Though, scoping your functions to just your environment
# is preferred.
#
# module Condenser::SassProcessor::Functions
#   def asset_path(path, options = {})
#   end
# end
module Condenser::Sass
  module Functions
  
    # Public: Generate a url for asset path.
    #
    # Defaults to Context#asset_path.
    def asset_path(path, options = {})
      condenser_context.link_asset(path)

      path = condenser_context.asset_path(path, options)
      query    = "?#{query}" if query
      fragment = "##{fragment}" if fragment
      "#{path}#{query}#{fragment}"
    end
    
    def asset_path_signature
      {
        "$path" => "String",
        "$options: ()" => 'Map'
      }
    end
    
    # Public: Generate a asset url() link.
    #
    # path - String
    def asset_url(path, options = {})
      "url(#{asset_path(path, options)})"
    end

    def asset_url_signature
      {
        "$path" => "String",
        "$options: ()" => 'Map'
      }
    end
    
    # Public: Generate url for image path.
    def image_path(path)
      asset_path(path, type: :image)
    end

    # Public: Generate a image url() link.
    def image_url(path)
      asset_url(path, type: :image)
    end

    # Public: Generate url for video path.
    def video_path(path)
      asset_path(path, type: :video)
    end

    # Public: Generate a video url() link.
    def video_url(path)
      asset_url(path, type: :video)
    end

    # Public: Generate url for audio path.
    def audio_path(path)
      asset_path(path, type: :audio)
    end

    # Public: Generate a audio url() link.
    def audio_url(path)
      asset_url(path, type: :audio)
    end

    # Public: Generate url for font path.
    def font_path(path)
      asset_path(path, type: :font)
    end

    # Public: Generate a font url() link.
    def font_url(path)
      asset_url(path, type: :font)
    end

    # Public: Generate url for javascript path.
    def javascript_path(path)
      asset_path(path, type: :javascript)
    end

    # Public: Generate a javascript url() link.
    def javascript_url(path)
      asset_url(path, type: :javascript)
    end

    # Public: Generate url for stylesheet path.
    def stylesheet_path(path)
      asset_path(path, type: :stylesheet)
    end

    # Public: Generate a stylesheet url() link.
    def stylesheet_url(path)
      asset_url(path, type: :stylesheet)
    end

    # Public: Generate a data URI for asset path.
    def asset_data_url(path)
      url = condenser_environment.asset_data_uri(path.value)
      Sass::Script::String.new("url(" + url + ")")
    end

    protected
      # Public: The Environment.
      #
      # Returns Condenser::Environment.
      def condenser_context
        options[:condenser][:context]
      end
    
      def condenser_environment
        options[:condenser][:environment]
      end

      # Public: Mutatable set of dependencies.
      #
      # Returns a Set.
      def condenser_dependencies
        options[:asset][:process_dependencies]
      end

  end
end