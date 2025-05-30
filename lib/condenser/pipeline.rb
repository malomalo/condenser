# frozen_string_literal: true

class Condenser
  module Pipeline
    
    CONFIG_VARS  = %w(mime_types extensions templates preprocessors transformers postprocessors minifiers exporters writers).map(&:to_sym)
    
    def self.prepended(base)
      base.extend(self)
      CONFIG_VARS.each do |var|
        base.instance_variable_set("@#{var}", {})
        base.send(:attr_reader, var)
        self.send(:attr_reader, var)
      end
    end
    
    def initialize(*args, **kws, &block)
      CONFIG_VARS.each do |var_name|
        original_var = self.class.instance_variable_get("@#{var_name}")
        new_var = original_var.dup
        
        if original_var.is_a?(Hash)
          original_var.each do |k, v|
            new_var[k] = v.dup if v.is_a?(Hash) || v.is_a?(Array)
          end
        end

        instance_variable_set("@#{var_name}", new_var)
      end
      super
    end
    
    def pipline_to_json(values)
      if values.is_a?(Hash)
        values.transform_values do |value|
          pipline_to_json(value)
        end
      elsif values.is_a?(Array)
        values.map do |value|
          pipline_to_json(value)
        end
      elsif values.is_a?(Class) || values.is_a?(Module)
        values.name
      elsif values.is_a?(String)
        @base ? values.delete_prefix(@base) : values
      elsif values.nil? || values == true || values == false || values.is_a?(Symbol) || values.is_a?(Integer) || values.is_a?(Float)
        values
      else
        { values.class.name => pipline_to_json(values.options) }
      end
    end
    
    def pipline_hash
      JSON.generate(pipline_to_json([
        @templates,
        @preprocessors,
        @transformers,
        @postprocessors,
        @minifiers,
        @exporters
      ]))
    end
    
    def pipline_digest
      @pipline_digest ||= Digest::MD5.hexdigest(pipline_hash)
    end
    
    def register_mime_type(mime_type, extensions: nil, extension: nil, charset: :default)
      extensions = Array(extensions || extension)

      @mime_types[mime_type] = { extensions: extensions, charset: charset }
      extensions.each { |ext| @extensions[ext] = mime_type }
    end
    
    def register_template(mime_type, engine)
      @templates[mime_type] = engine
    end

    def register_preprocessor(mime_type, engine)
      @preprocessors[mime_type] ||= []
      @preprocessors[mime_type] << engine
    end
    
    def unregister_preprocessor(mime_type, engine=nil)
      if engine.nil?
        @preprocessors[mime_type].clear
      else
        @preprocessors[mime_type]&.reject! { |e| e == engine || e.is_a?(engine) }
      end
    end

    def register_transformer(from_mime_type, to_mime_type, engine)
      @transformers[from_mime_type] ||= {}
      @transformers[from_mime_type][to_mime_type] = engine
    end
    
    def register_postprocessor(mime_type, engine)
      @postprocessors[mime_type] ||= []
      @postprocessors[mime_type] << engine
    end
    
    def register_exporter(mime_type, engine)
      @exporters[mime_type] ||= []
      @exporters[mime_type] << engine
    end
    
    def unregister_exporter(mime_type, engine=nil)
      if engine.nil?
        @exporters[mime_type].clear
      else
        @exporters[mime_type]&.reject! { |e| e == engine || e.is_a?(engine) }
      end
    end
    
    def register_minifier(mime_type, engine)
      @minifiers[mime_type] = engine
    end
    
    def minifier_for(mime_type)
      @minifiers[mime_type]
    end
    
    def unregister_minifier(mime_type)
      @minifiers[mime_type] = nil
    end
    
    def register_writer(engine)
      Array(engine.mime_types).each do |mime_type|
        @writers[mime_type] ||= []
        @writers[mime_type] << engine
      end
    end
        
    def unregister_writer(engine, for_mime_types: [])
      mime_types = @writers.keys if mime_types.nil?
      Array(for_mime_types || @writers.keys).each do |mime_type|
        @writers[mime_type].select! do |writer|
          if engine.nil? || engine == writer[0] || writer[0].is_a?(engine)
            if added_mime_types.nil? || added_mime_types == writer[1]
              false
            else
              true
            end
          else
            true
          end
        end
      end
    end
    
    def clear_pipeline
      (CONFIG_VARS - [:mime_types, :extensions]).each { |v| self.instance_variable_set("@#{v}", {}) }
    end
    
  end
end
