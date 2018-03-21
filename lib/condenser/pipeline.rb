class Condenser
  module Pipeline
    
    CONFIG_VARS  = %w(mime_types extensions templates preprocessors transformers postprocessors minifiers exporters writers).map(&:to_sym)
    
    def self.included(base)
      base.extend(self)
      CONFIG_VARS.each do |var|
        base.instance_variable_set("@#{var}", {})
        base.send(:attr_reader, var)
        self.send(:attr_reader, var)
      end
    end
    
    def initialize(root)
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
    
    def unregister_preprocessor(mime_type, engine)
      @preprocessors[mime_type].delete(engine)
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
      @exporters[mime_type] = engine
    end
    
    def register_minifier(mime_type, engine)
      @minifiers[mime_type] ||= []
      @minifiers[mime_type] = engine
    end
    
    def register_writer(mime_types, engine, added_mime_types=nil)
      Array(mime_types).each do |mime_type|
        @writers[mime_type] ||= []
        @writers[mime_type] << [engine, added_mime_types || []]
      end
    end
    
    def clear_pipeline
      (CONFIG_VARS - [:mime_types, :extensions]).each { |v| self.instance_variable_set("@#{v}", {}) }
    end
    
  end
end