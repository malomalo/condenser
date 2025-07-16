# frozen_string_literal: true

class Condenser::JSAnalyzer

  include Condenser::ParseHelpers
  
  def self.setup(env)
  end
  
  def self.call(environment, input)
    new.call(environment, input)
  end
  
  def call(environment, input)
    seek(0)
    @sourcefile = input[:source_file]
    @source = input[:source]
    @stack =  [:main]
    @previous = [[]]

    input[:linked_assets] ||= Set.new
    input[:export_dependencies] ||= Set.new

    scan_until(/\A(\/\/[^\n]*(\n|\z))*/)
    if matched
      directives = matched.split(/\n/).map { |l| l.delete_prefix("//").strip }
      directives.each do |directive|
        if directive.start_with?('depends_on')
          input[:process_dependencies] << directive.sub(/\Adepends_on\s+/, '')
        end
      end
    end
    
    last_postion = nil
    last_stack = nil
    while !eos?
      case @stack.last

      when :tick_value
        scan_until(/(\$\{|\`)/)
        case matched
        when '`'
          @stack.pop if pre_match[-1] != "\\" && pre_match[-1] != "\\"
        when '${'
          @stack << :tick_statment
        end

      when :import
        scan_until(/[\"\'\`\(]/)
        dynamic = if matched == "("
          scan_until(/[\"\'\`]/)
          true
        end
        
        filename = case matched
        when "\""
          double_quoted_value
        when "'"
          single_quoted_value
        when '`'
          tick_quoted_value
        end

        if dynamic
          input[:process_dependencies] << filename
          input[:linked_assets] << filename 
        else
          input[:export_dependencies] << filename
        end
        scan_until(/(;|\n|\))/)
        @stack.pop

      when :export
        input[:exports] = true;
        input[:default_export] = true if gobble(/\s+default/)
        gobble(/\s+/)

        if gobble(/\{/)
          @stack << :brackets
          @previous << []
        elsif gobble(/\*/)
          @stack << :export_from
        else
          @stack.pop
        end

      when :export_from
        if gobble(/\s+from\s+/)
          scan_until(/\"|\'/)
          input[:export_dependencies] <<  case matched
          when '"'
            double_quoted_value
          when "'"
            single_quoted_value
          end
        end
        @stack.pop
        @stack.pop
        
      else
        scan_until(/(\/\/|\/\*|\/|\(|\)|\{|\}|\"|\'|\`|export(?![[:alnum:]])|import(?![[:alnum:]])|\z)/)

        case matched
        when '//'
          scan_until(/(\n|\z)/)
          @previous.last << :single_line_comment
        when '/*'
          scan_until(/\*\//)
          @previous.last << :multi_line_comment
        when '"'
          double_quoted_value
          @previous.last << :double_quoted_value
        when "'"
          single_quoted_value
          @previous.last << :single_quoted_value
        when '`'
          @stack << :tick_value
        when '/'
          if pre_match.match(/(\W|\A)(void|typeof|return|export)\z/)
            regex_value
          elsif match_index = @source.rindex(/(\w+|\)|\])\s*\//, @index)
            match = @source.match(/(\w+|\)|\])\s*\//, match_index)
            if match[1] =~ /\)\z/ && @previous.last.last == :loop
              regex_value
            elsif %w(void typeof return export).include?(match[1])
              regex_value
            elsif match[0].length + match_index != @index
              regex_value
            elsif [:single_line_comment, :multi_line_comment].include?(@previous.last.last)
              regex_value
            end
          else
            regex_value
          end
        when '('
          @stack << if pre_match =~ /\W*(for|while)\s*\z/
            :loop
          else
            :parenthesis
          end
        when ')'
          raise unexptected_token(")") if @stack.last != :parenthesis && @stack.last != :loop
          @previous.last << @stack.pop
        when '{'
          @stack.push :brackets
          @previous << []
        when '}'
          case @stack.last
          when :tick_statment
            @stack.pop
          when :brackets
            @stack.pop
            @previous.pop
            @previous.last << :brackets
            if @stack.last == :export
              @stack.pop
              @stack << :export_from if peek(/\s+from/i)
            end
          else
            raise unexptected_token("}")
          end
        when 'export'
          if @stack.last == :main
            @stack << :export
          end
        when 'import'
          @stack << :import
        else
          @stack.pop
        end
      end

      if last_postion == @index && last_stack == @stack.last
        syntax_error = Condenser::SyntaxError.new("Error parsing JS file with JSAnalyzer")
        syntax_error.instance_variable_set(:@path, @sourcefile)
        raise Condenser::SyntaxError, "Error parsing JS file with JSAnalyzer"
      else
        last_postion = @index
        last_stack = @stack.last
      end
    end
    
    raise Condenser::SyntaxError, "Unexpected EOF" if !@stack.empty? && @stack.last != :main
  end
  
  def unexptected_token(token)
    start = (@source.rindex("\n", @old_index) || 0) + 1
    uptop = @source.index("\n", @index) || (@old_index + @matched.length)
    lineno = @source[0..start].count("\n") + 1

    message = "Unexpected token #{token} #{@sourcefile} #{lineno.to_s.rjust(4)}:#{(@index-start)}"
    message << "\n#{lineno.to_s.rjust(4)}: " << @source[start..uptop]
    message << "\n      #{'-'* ([@index-1-start,1].max)}#{'^'*([@matched.length,1].max)}"
    message << "\n"
    
    syntax_error = Condenser::SyntaxError.new(message)
    syntax_error.instance_variable_set(:@path, @sourcefile)
    syntax_error
  end
  
  def double_quoted_value
    ret_value = String.new

    while scan_until(/[\"\n\\]/)
      case matched
      when "\n"
        raise unexptected_token("\\n")
      when "\\"
        ret_value << pre_match << matched << gobble(1)
      when "\""
        ret_value << pre_match
        return ret_value
      else
        ret_value << match
      end
    end
  end
  
  def single_quoted_value
    ret_value = String.new

    while scan_until(/[\'\n]/)
      if matched == "\n"
        raise unexptected_token("\\n")
      elsif matched == "\'" && pre_match[-1] != "\\"
        ret_value << pre_match
        return ret_value
      else
        ret_value << pre_match
      end
    end
  end

  def tick_quoted_value
    ret_value = String.new

    while scan_until(/[\`]/)
      if matched == "\`" && pre_match[-1] != "\\"
        ret_value << pre_match
        return ret_value
      else
        ret_value << pre_match
      end
    end
  end
  
  def regex_value
    ret_value = String.new

    regex_stack =  ['/']
    while !regex_stack.empty?
      
      scan_until(/[\/\[\]]/)
      escaped = pre_match[-1] == "\\" && pre_match[-2] != "\\"
      ret_value << pre_match
      case matched
      when "["
        regex_stack << '[' if !escaped && regex_stack.last != "["
        ret_value << matched
      when "]"
        regex_stack.pop if !escaped && regex_stack.last == "["
        ret_value << matched
      when "/"
        # From https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Regular_expressions/Character_class
        # 
        # The lexical grammar does a very rough parse of regex literals, so
        # that it does not end the regex literal at a / character which appears
        # within a character class. This means /[/]/ is valid without needing
        # to escape the /.
        if !escaped && regex_stack.last != "[" && regex_stack.pop != "/"
          raise unexptected_token("/")
        else
          ret_value << matched
        end
      end
    end

    ret_value
  end

end