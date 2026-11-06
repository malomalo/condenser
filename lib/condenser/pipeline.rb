# frozen_string_literal: true

require 'json'

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
      elsif values.is_a?(Module)
        values.name
      elsif values.is_a?(String)
        @base ? values.delete_prefix(@base) : values
      elsif values.nil? || values == true || values == false || values.is_a?(Symbol) || values.is_a?(Integer) || values.is_a?(Float)
        values
      else
        { values.class.name => pipline_to_json(values.options) }
      end
    end
    
    # A digest of just the given part of the pipeline, as [role, mime type,
    # processor] entries (see Asset#pipeline_processors), so an asset's cache
    # only depends on the processors that process it, and of the sourcemap
    # setting, since processors make a map (SassTransformer) when it's on.
    def pipeline_digest_for(entries)
      versioned_digest(JSON.generate([entries.map { |role, mime_type, processor|
        [role, mime_type, pipline_to_json(processor)]
      }, { sourcemap: sourcemap }]))
    end

    # A digest of what exporting +mime_type+ uses, its exporters, minifier and
    # the sourcemap setting, or nil if it has neither exporters nor minifier
    # and source maps are off. With them on, an export without exporters or
    # a minifier still gets the map's comment, so the setting is in its etag.
    def export_pipeline_digest(mime_type)
      exporters = @exporters[mime_type] || []
      minifier = @minifiers[mime_type]
      return if exporters.empty? && minifier.nil? && !sourcemap

      versioned_digest(JSON.generate(pipline_to_json([exporters, minifier, { sourcemap: sourcemap }])))
    end

    # Condenser's version is part of every pipeline digest, since its own
    # processors can change between releases without their options changing.
    def versioned_digest(json)
      Digest::MD5.hexdigest(JSON.generate([Condenser::VERSION, json]))
    end
    
    def register_mime_type(mime_type, extensions: nil, extension: nil, charset: :default)
      extensions = Array(extensions || extension)

      @mime_types[mime_type] = { extensions: extensions, charset: charset }
      extensions.each { |ext| @extensions[ext] = mime_type }
      @reverse_mapping = nil
    end
    
    # Processors are registered as instances of Condenser::Processor, so a
    # class raises an ArgumentError.
    def check_processor!(engine)
      return if engine.is_a?(Condenser::Processor)
      raise ArgumentError, "#{engine.inspect} isn't a Condenser::Processor instance#{" (register #{engine.name}.new)" if engine.is_a?(Class)}"
    end
    private :check_processor!

    def register_template(mime_type, engine)
      check_processor!(engine)
      @templates[mime_type] = engine
      @reverse_mapping = nil
    end

    def register_preprocessor(mime_type, engine)
      check_processor!(engine)
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
      check_processor!(engine)
      @transformers[from_mime_type] ||= {}
      @transformers[from_mime_type][to_mime_type] = engine
      @reverse_mapping = nil
    end
    
    def register_postprocessor(mime_type, engine)
      check_processor!(engine)
      @postprocessors[mime_type] ||= []
      @postprocessors[mime_type] << engine
    end
    
    def register_exporter(mime_type, engine)
      check_processor!(engine)
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
      check_processor!(engine)
      @minifiers[mime_type] = engine
    end
    
    def minifier_for(mime_type)
      @minifiers[mime_type]
    end
    
    def unregister_minifier(mime_type)
      @minifiers[mime_type] = nil
    end
    
    def register_writer(engine)
      if engine.is_a?(Class)
        raise ArgumentError, "#{engine.inspect} is a class, register #{engine.name}.new"
      end
      Array(engine.accepts).each do |mime_type|
        @writers[mime_type] ||= []
        @writers[mime_type] << engine
      end
    end
        
    # Removes +engine+, a writer or a writer class, for +for_mime_types+, or
    # every mime type if none are given.
    # A class matches only its own instances, so unregistering FileWriter
    # leaves the compressing writers that subclass it.
    def unregister_writer(engine, for_mime_types: nil)
      Array(for_mime_types || @writers.keys).each do |mime_type|
        @writers[mime_type]&.reject! { |w| w == engine || (engine.is_a?(Class) && w.instance_of?(engine)) }
      end
    end
    
    def clear_pipeline
      (CONFIG_VARS - [:mime_types, :extensions]).each { |v| self.instance_variable_set("@#{v}", {}) }
    end
    
  end
end
