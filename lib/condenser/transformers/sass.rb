# frozen_string_literal: true

module Condenser::Sass
  autoload :Functions, 'condenser/transformers/sass/functions'
  autoload :Importer, 'condenser/transformers/sass/importer'
  autoload :RelativeImports, 'condenser/transformers/sass/relative_imports'

  def self.require_sass_embedded!(processor)
    require "sass-embedded" unless defined?(::Sass::Compiler)
  rescue LoadError
    raise LoadError, "#{processor} requires the sass-embedded gem, add `gem 'sass-embedded'` to your Gemfile"
  end

  # A Sass logger that sends Dart Sass deprecation warnings and `@debug` to
  # the environment's logger at debug level and other warnings at warn level.
  class Logger
    def initialize(logger)
      @logger = logger
    end

    def warn(message, context)
      if context.deprecation
        @logger.debug { "Sass deprecation warning [#{context.deprecation_type}]#{location(context)}: #{message}" }
      elsif message.match?(/\A\d+ repetitive deprecation warnings omitted/)
        @logger.debug { "Sass: #{message}" }
      else
        @logger.warn { "Sass warning#{location(context)}: #{message}" }
      end
    end

    def debug(message, context)
      @logger.debug { "Sass debug#{location(context)}: #{message}" }
    end

    private

    def location(context)
      if context.span&.url
        " #{context.span.url}:#{context.span.start.line + 1}"
      elsif context.respond_to?(:stack) && context.stack && !context.stack.empty?
        " #{context.stack.lines.first.split(/\s{2,}/).first.strip}"
      end
    end
  end
end
