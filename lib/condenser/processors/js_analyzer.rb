# frozen_string_literal: true

require 'strscan'

class Condenser::JSAnalyzer

  WHITESPACE    = /[\s\p{Zs}\uFEFF\u2028\u2029]+/
  LINE_COMMENT  = /\/\/[^\n\r\u2028\u2029]*/
  BLOCK_COMMENT = /\/\*.*?\*\//m
  HTML_COMMENT  = /<!--[^\n\r\u2028\u2029]*/
  SKIP          = /(?:[\s\p{Zs}\uFEFF\u2028\u2029]+|\/\/[^\n\r\u2028\u2029]*|\/\*.*?\*\/)*/m

  ID_START      = /[\p{L}\p{Nl}$_]|\\u\h{4}|\\u\{\h+\}/
  ID_CONTINUE   = /[\p{L}\p{Nl}\p{Mn}\p{Mc}\p{Nd}\p{Pc}$\u200C\u200D]|\\u\h{4}|\\u\{\h+\}/
  IDENTIFIER    = /(?:#{ID_START})(?:#{ID_CONTINUE})*/
  NUMBER        = /(?:0[xXoObB][\h_]+|(?:\d[\d_]*(?:\.[\d_]*)?|\.\d[\d_]*)(?:[eE][+-]?[\d_]+)?)n?/
  PUNCTUATOR    = />>>=|\.\.\.|===|!==|\*\*=|<<=|>>=|>>>|&&=|\|\|=|\?\?=|=>|==|!=|<=|>=|&&|\|\||\?\?|\?\.(?!\d)|\+\+|--|\+=|-=|\*=|%=|&=|\|=|\^=|\*\*|<<|>>|[;,<>+\-*%&|^!~?:=.@#]/
  DOUBLE_QUOTED = /"([^"\\\n\r]*(?:\\(?:\r\n|.)[^"\\\n\r]*)*)"/m
  SINGLE_QUOTED = /'([^'\\\n\r]*(?:\\(?:\r\n|.)[^'\\\n\r]*)*)'/m
  UNTERMINATED  = /["'][^\\\n\r]*(?:\\(?:\r\n|.)[^\\\n\r]*)*/m
  TEMPLATE      = /[^`\\$]*(?:(?:\\.|\$(?!\{))[^`\\$]*)*/m
  REGEX         = /\/(?:[^\/\\\[\n\r]|\\[^\n\r]|\[(?:[^\]\\\n\r]|\\[^\n\r])*\])+\/(?:#{ID_CONTINUE})*/
  DIVISION      = /\/=?/

  COLON_AHEAD   = /#{SKIP}:/
  PAREN_AHEAD   = /#{SKIP}\(/
  BRACE_AHEAD   = /#{SKIP}\{/
  STAR_AHEAD    = /#{SKIP}\*/
  META_AHEAD    = /#{SKIP}\.#{SKIP}meta(?!#{ID_CONTINUE})/
  DEFAULT_AHEAD = /#{SKIP}default(?!#{ID_CONTINUE})/
  FROM_AHEAD    = /#{SKIP}from(?!#{ID_CONTINUE})/
  IMPORT_AHEAD  = /#{SKIP}(?:[{*"']|#{ID_START})/

  # A `/` after a :value (or `from`) is division, otherwise it starts a regex
  KEYWORDS = %w(return typeof instanceof in of new delete void throw case do else yield await extends default).to_h { |k| [k, :keyword] }
  KEYWORDS.merge!(%w(if for while with).to_h { |k| [k, :control] })
  KEYWORDS['from'] = :from
  KEYWORDS.freeze

  def self.setup(env)
  end
  
  def self.call(environment, input)
    new.call(environment, input)
  end
  
  def call(environment, input)
    @input = input
    @sourcefile = input[:source_file]
    @source = scannable(input[:source])
    @ss = StringScanner.new(@source)
    @stack = []
    @import_sources = []
    @prev = nil
    @dynamic_import = false
    @export_brace = false
    @module_source = false

    input[:linked_assets] ||= Set.new
    input[:export_dependencies] ||= Set.new

    if directives = @ss.scan(/(?:\/\/[^\n]*(?:\n|\z))+/)
      directives.split(/\n/).map { |l| l.delete_prefix("//").strip }.each do |directive|
        if directive.start_with?('depends_on')
          input[:process_dependencies] << directive.sub(/\Adepends_on\s+/, '')
        end
      end
    else
      @ss.skip(/#![^\n]*/)
    end

    until @ss.eos?
      next if @ss.skip(WHITESPACE)

      if word = @ss.scan(IDENTIFIER)
        identifier(word)
        next
      end

      case @ss.peek(1)
      when '/'
        if @ss.skip(LINE_COMMENT)
        elsif @ss.skip(BLOCK_COMMENT)
        elsif @ss.match?(/\/\*/)
          raise syntax_error("Unexpected EOF", @source.bytesize)
        elsif @prev == :value || @prev == :from || !@ss.skip(REGEX)
          @ss.skip(DIVISION)
          @prev = :operator
        else
          @prev = :value
        end
      when '"', "'"
        if @ss.scan(@ss.peek(1) == '"' ? DOUBLE_QUOTED : SINGLE_QUOTED)
          string(@ss[1])
        else
          @ss.skip(UNTERMINATED)
          raise unexpected_token(@ss.eos? ? "EOF" : "\\n")
        end
      when '`'
        @ss.skip(/`/)
        template
      when '('
        @ss.skip(/\(/)
        if @dynamic_import
          @stack << :import_paren
          @import_sources << nil
          @dynamic_import = false
          @prev = :import_paren
        else
          @stack << (@prev == :control ? :control_paren : :paren)
          @prev = :operator
        end
      when ')'
        close_paren
      when '['
        @ss.skip(/\[/)
        @stack << :bracket
        @prev = :operator
      when ']'
        raise unexpected_token("]") if @stack.last != :bracket
        @ss.skip(/\]/)
        @stack.pop
        @prev = :value
      when '{'
        @ss.skip(/\{/)
        @stack << (@export_brace ? :export_brace : :brace)
        @export_brace = false
        @prev = :operator
      when '}'
        close_brace
      else
        if @ss.skip(NUMBER)
          @prev = :value
        elsif @ss.skip(HTML_COMMENT)
        elsif punctuator = @ss.scan(PUNCTUATOR)
          @prev = case punctuator
          when '.', '?.', '#' then :dot
          when '++', '--' then :value
          else :operator
          end
        else
          raise unexpected_token(@ss.peek(1))
        end
      end
    end

    raise syntax_error("Unexpected EOF", @source.bytesize) if !@stack.empty?
  end

  private

  def scannable(source)
    source = source.encode(Encoding::UTF_8) if !source.encoding.ascii_compatible?
    source = source.dup.force_encoding(Encoding::UTF_8) if source.encoding != Encoding::UTF_8
    source.valid_encoding? ? source : source.scrub
  end

  def identifier(word)
    if @prev == :dot
      @prev = :value
    elsif word == 'import'
      import_keyword
    elsif word == 'export'
      export_keyword
    elsif word == 'await' && @prev == :control
    else
      @prev = KEYWORDS[word] || :value
    end
  end

  # `import` that isn't `obj.import`, `{ import: x }`, or a class field
  def import_keyword
    if @ss.match?(COLON_AHEAD)
      @prev = :value
    elsif @ss.match?(META_AHEAD)
      @input[:type] = "module"
      @prev = :value
    elsif @ss.match?(PAREN_AHEAD)
      @dynamic_import = true
      @prev = :import
    elsif @ss.match?(IMPORT_AHEAD)
      @input[:type] = "module"
      @module_source = true
      @prev = :import
    else
      @prev = :value
    end
  end

  def export_keyword
    if !@stack.empty? || @ss.match?(COLON_AHEAD)
      @prev = :value
      return
    end

    @input[:type] = "module"
    @input[:exports] = true
    @input[:default_export] = true if @ss.match?(DEFAULT_AHEAD)
    if @ss.match?(STAR_AHEAD)
      @module_source = true
    elsif @ss.match?(BRACE_AHEAD)
      @export_brace = true
    end
    @prev = :keyword
  end

  def string(value)
    if @prev == :import_paren
      @import_sources[-1] = value
    elsif @module_source && (@prev == :import || @prev == :from)
      @input[:export_dependencies] << value
      @module_source = false
    end
    @prev = :value
  end

  def template
    start = @ss.pos
    @ss.skip(TEMPLATE)
    if @ss.skip(/`/)
      @import_sources[-1] = @source.byteslice(start, @ss.pos - start - 1) if @prev == :import_paren
      @prev = :value
    elsif @ss.skip(/\$\{/)
      @stack << :template
      @prev = :operator
    else
      raise syntax_error("Unexpected EOF", @source.bytesize)
    end
  end

  def close_paren
    @ss.skip(/\)/)
    case @stack.pop
    when :paren
      @prev = :value
    when :control_paren
      @prev = :operator
    when :import_paren
      source = @import_sources.pop
      # `import(...) { ... }` in a class or object body is a method named import
      if @stack.last != :brace || !@ss.match?(BRACE_AHEAD)
        @input[:type] = "module"
        if source
          @input[:process_dependencies] << source
          @input[:linked_assets] << source
        end
      end
      @prev = :value
    else
      @ss.unscan
      raise unexpected_token(")")
    end
  end

  def close_brace
    case @stack.last
    when :template
      @ss.skip(/\}/)
      @stack.pop
      template
    when :brace
      @ss.skip(/\}/)
      @stack.pop
      @prev = :operator
    when :export_brace
      @ss.skip(/\}/)
      @stack.pop
      @module_source = @ss.match?(FROM_AHEAD)
      @prev = :operator
    else
      raise unexpected_token("}")
    end
  end

  def unexpected_token(token)
    syntax_error("Unexpected token #{token}", @ss.pos)
  end

  def syntax_error(message, pos)
    line_start = (@source.byterindex("\n", [pos - 1, 0].max) || -1) + 1
    line_start = 0 if pos == 0
    line_end = @source.byteindex("\n", pos) || @source.bytesize
    lineno = @source.byteslice(0, line_start).count("\n") + 1
    column = @source.byteslice(line_start, pos - line_start).length

    message = "#{message} #{@sourcefile} #{lineno.to_s.rjust(4)}:#{column}"
    message << "\n#{lineno.to_s.rjust(4)}: " << @source.byteslice(line_start, line_end - line_start)
    message << "\n      #{'-' * column}^\n"

    syntax_error = Condenser::SyntaxError.new(message)
    syntax_error.instance_variable_set(:@path, @sourcefile)
    syntax_error
  end

end
