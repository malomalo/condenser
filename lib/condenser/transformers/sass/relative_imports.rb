# frozen_string_literal: true

# Finds the relative URLs (starting with `./` or `../`) of a stylesheet's
# `@import`, `@use` and `@forward` rules so they can be replaced before Dart
# Sass, which drops a leading `./`, sees them.
#
# The scanner skips comments, strings and `url()`, and leaves plain CSS
# imports alone: `url()`, `.css` and `http(s)://` URLs, interpolated URLs and
# URLs followed by a media query.
#
#   Condenser::Sass::RelativeImports.rewrite(source) { |url| "new-url" }
class Condenser::Sass::RelativeImports
  RULE = /\G@(import|use|forward)(?![\w-])/n
  QUOTES = ['"', "'"].freeze
  SPECIAL = %r{/[/*]|["'@]|url\(}in

  # Returns +source+ with each relative URL replaced by the block's result
  # (or left as is when the block returns nil).
  def self.rewrite(source, indented: false, &block)
    new(source, indented).rewrite(&block)
  end

  # Scans the bytes, all the syntax looked for is ASCII.
  def initialize(source, indented)
    @encoding = source.encoding
    @source = source.b
    @indented = indented
  end

  def rewrite
    replacements = []
    i = 0
    while (i = @source.index(SPECIAL, i))
      if (j = skip_comment(i) || skip_string(i) || skip_url(i))
        i = j
      elsif @source[i] == '@' && (i == 0 || @source[i - 1] !~ /[\w-]/) && (m = RULE.match(@source, i))
        i = scan_rule(m[1], m.end(0), replacements)
      else
        i += 1
      end
    end

    result = @source.dup
    replacements.reverse_each do |from, to, url, quote|
      next unless (new_url = yield(url.force_encoding(@encoding)))
      result[from...to] = "#{quote}#{new_url}#{quote}".b
    end
    result.force_encoding(@encoding)
  end

  private

  # Records the URLs of the rule starting at +i+ and returns where scanning
  # should continue.
  def scan_rule(rule, i, replacements)
    loop do
      i = skip_space(i)
      if QUOTES.include?(@source[i])
        from, to = i, skip_string(i)
        quote, url = @source[i], @source[(i + 1)...(to - 1)]
      elsif (to = skip_url(i))
        from, url = i, nil
      elsif @indented && rule == 'import' && @source[i] =~ /[^\s,;]/
        from = i
        to = i
        to += 1 while to < @source.size && @source[to] !~ /[\s,;]/
        quote, url = '"', @source[from...to]
      else
        return i
      end

      if rule != 'import'
        replacements << [from, to, url, quote] if relative?(url) && url !~ /#\{/
        return to
      end

      after = skip_space(to)
      last = after >= @source.size || [';', "\n", "\r", '}', '{'].include?(@source[after]) || @source[after, 2] == '//'
      plain = url.nil? || (!last && @source[after] != ',') || plain_css?(url)
      replacements << [from, to, url, quote] if relative?(url) && !plain && url !~ /#\{/
      return after if @source[after] != ','

      i = after + 1
    end
  end

  def relative?(url)
    url&.start_with?('./', '../')
  end

  def plain_css?(url)
    url.end_with?('.css') || url.match?(%r{\A(https?:)?//}i)
  end

  # Skips spaces and /* */ comments, and newlines unless the syntax is
  # indented, where a newline ends a rule.
  def skip_space(i)
    loop do
      if @source[i] == ' ' || @source[i] == "\t" || (!@indented && (@source[i] == "\n" || @source[i] == "\r"))
        i += 1
      elsif @source[i, 2] == '/*'
        close = @source.index('*/', i + 2)
        return @source.size if close.nil?
        i = close + 2
      else
        return i
      end
    end
  end

  def skip_comment(i)
    return unless @source[i] == '/' && (@source[i + 1] == '/' || @source[i + 1] == '*')

    if @indented && @source[line_start(i)...i].strip.empty?
      skip_indented_block(i)
    elsif @source[i + 1] == '/'
      @source.index("\n", i) || @source.size
    else
      close = @source.index('*/', i + 2)
      close ? close + 2 : (@indented ? (@source.index("\n", i) || @source.size) : @source.size)
    end
  end

  # In the indented syntax a comment at the start of a line also covers the
  # lines indented under it.
  def skip_indented_block(i)
    indent = i - line_start(i)
    pos = @source.index("\n", i) || @source.size
    while pos < @source.size
      next_end = @source.index("\n", pos + 1) || @source.size
      line = @source[(pos + 1)...next_end]
      break unless line.strip.empty? || line[/\A[ \t]*/].size > indent
      pos = next_end
    end
    pos
  end

  def line_start(i)
    i == 0 ? 0 : (@source.rindex("\n", i - 1) || -1) + 1
  end

  def skip_string(i)
    quote = @source[i]
    return unless QUOTES.include?(quote)

    j = i + 1
    while j < @source.size
      case @source[j]
      when '\\' then j += 2
      when quote then return j + 1
      when "\n" then return j
      else j += 1
      end
    end
    j
  end

  def skip_url(i)
    return unless @source[i, 4].casecmp?('url(') && (i == 0 || @source[i - 1] !~ /[\w-]/)

    j = i + 4
    while j < @source.size && @source[j] != ')'
      j = skip_string(j) || (j + 1)
    end
    j + 1
  end
end
