# frozen_string_literal: true

# Public: Functions available in Sass with dashes (`asset-path()`). They take
# Sass::Values and return a Sass::Value or String; the Sass signature comes
# from the parameters or a `<name>_signature` method.
module Condenser::Sass
  module Functions

    # Public: Generate a url for asset path.
    #
    # Defaults to Context#asset_path.
    def asset_path(path, options = {})
      path = sass_to_ruby(path)
      condenser_context.link_asset(path)

      ::Sass::Value::String.new(condenser_context.asset_path(path, sass_to_ruby(options)), quoted: true)
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
      ::Sass::Value::String.new("url(#{asset_path(path, options).text})", quoted: false)
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
      url = condenser_context.asset_data_uri(sass_to_ruby(path))
      ::Sass::Value::String.new("url(#{url})", quoted: false)
    end

    protected
      # Public: The Environment.
      #
      # Returns Condenser::Environment.
      def condenser_context
        @context
      end

      def condenser_environment
        @environment
      end

      # Public: Mutatable set of dependencies.
      #
      # Returns a Set.
      def condenser_dependencies
        @asset[:process_dependencies]
      end

      # Converts a Sass::Value to a Ruby String, Numeric, Array or Hash (with
      # Symbol keys). Other values are returned unchanged.
      def sass_to_ruby(value)
        case value
        when ::Sass::Value::String then value.text
        when ::Sass::Value::Number then value.value
        when ::Sass::Value::Map then value.contents.to_h { |k, v| [sass_to_ruby(k).to_s.to_sym, sass_to_ruby(v)] }
        when ::Sass::Value::List then value.to_a.empty? ? {} : value.to_a.map { |v| sass_to_ruby(v) }
        when ::Sass::Value::Null then nil
        else value
        end
      end

  end
end
