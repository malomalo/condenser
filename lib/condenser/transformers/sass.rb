# frozen_string_literal: true

require 'pathname'
require 'uri'

module Condenser::Sass
  autoload :Functions, 'condenser/transformers/sass/functions'
  autoload :Importer, 'condenser/transformers/sass/importer'
  autoload :RelativeImports, 'condenser/transformers/sass/relative_imports'

  def self.require_sass_embedded!(processor)
    require "sass-embedded" unless defined?(::Sass::Compiler)
  rescue LoadError
    raise LoadError, "#{processor} requires the sass-embedded gem, add `gem 'sass-embedded'` to your Gemfile"
  end

  # The version of Dart Sass, or nil if sass-embedded isn't installed. The
  # gem's version is the version of the Dart Sass it runs.
  def self.version
    require 'sass/embedded/version' unless defined?(::Sass::Embedded::VERSION)
    ::Sass::Embedded::VERSION
  rescue LoadError
  end

  INTERNAL_URL = %r{condenser(?:-[a-z]+)*:/([^\s"'?;,)]*)(?:\?[^\s"';,)]*)?}
  RELATIVE_URL = %r{condenser-relative:/([^\s"'?;,)]*)(?:\?\d+)?}

  # Returns a Sass::CompileError like +error+ whose message starts with the
  # stylesheet, line and column and has the source line, showing condenser's
  # internal URLs as filenames and relative imports as written. +filename+ is
  # used when the error has no URL.
  def self.compile_error(error, filename)
    span = error.span
    name = span&.url ? display_urls(span.url) : filename
    dir = File.dirname(name)

    message = if span
      "#{name}:#{span.start.line + 1}:#{span.start.column + 1}: #{display_urls(error.message, dir)}#{snippet(span, dir)}"
    else
      "#{name}: #{display_urls(error.message, dir)}"
    end
    stack = error.sass_stack && display_stack(error.sass_stack)
    message += "\n#{stack.gsub(/^(?=.)/, '  ').chomp}" if stack && !stack.strip.empty?

    ::Sass::CompileError.new(message, nil, stack, span, error.loaded_urls)
  end

  # Replaces condenser's internal URLs in +text+ with filenames, and when
  # +dir+ is given relative import URLs with the relative URL written in a
  # stylesheet in +dir+.
  def self.display_urls(text, dir = nil)
    text = text.gsub(RELATIVE_URL) { relative_url(URI.decode_uri_component($1), dir) } if dir
    text.gsub(INTERNAL_URL) { URI.decode_uri_component($1) }
  end

  # Dart Sass aligns the stack's members, so realign them after the URLs
  # change length.
  def self.display_stack(stack)
    frames = display_urls(stack).lines.map { |l| l.chomp.split(/\s{2,}/, 2) }
    width = frames.map { |location, _| location.size }.max
    frames.map { |location, member| member ? "#{location.ljust(width)}  #{member}\n" : "#{location}\n" }.join
  end

  def self.relative_url(name, dir)
    path = Pathname.new(name).relative_path_from(Pathname.new(dir)).to_s
    path.start_with?('../') ? path : "./#{path}"
  end

  def self.snippet(span, dir)
    line = span.context&.lines&.first&.chomp
    return '' if line.nil? || line.size < span.start.column

    stop = span.end.line == span.start.line ? [span.end.column, line.size].min : line.size
    before, marked, after = [line[0...span.start.column], line[span.start.column...stop], line[stop..]].map { |s| display_urls(s, dir) }
    number = (span.start.line + 1).to_s
    margin = ' ' * number.size
    "\n#{margin} ╷\n#{number} │ #{before}#{marked}#{after}\n#{margin} │ #{before.gsub(/[^\t]/, ' ')}#{'^' * [marked.size, 1].max}\n#{margin} ╵"
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
