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
    while !eos?
      case @stack.last

      when :tick_value
        scan_until(/(\$\{|\`)/)
        case matched
        when '`'
          @stack.pop
        when '${'
          @stack << :tick_statment
        end

      when :import
        scan_until(/[\"\'\`]/)
        input[:export_dependencies] << case matched
        when "\""
          double_quoted_value
        when "'"
          single_quoted_value
        when '`'
          tick_quoted_value
        end
        scan_until(/(;|\n)/)
        @stack.pop

      when :export
        input[:exports] = true;
        input[:default_export] = true if gobble(/\s+default/)
        gobble(/\s+/)

        if gobble(/(\{|\*)/)
          scan_until(/\}/) if matched.strip == "{"
          if gobble(/\s+from\s+/)
            scan_until(/\"|\'/)
            input[:export_dependencies] <<  case matched
            when '"'
              double_quoted_value
            when "'"
              single_quoted_value
            end
          end
        end
        
        @stack.pop
      else
        scan_until(/(\/\/|\/\*|\/|\(|\)|\{|\}|\"|\'|\`|export|import|\z)/)

        case matched
        when '//'
          scan_until(/(\n|\z)/)
        when '/*'
          scan_until(/\*\//)
        when '"'
          double_quoted_value
        when "'"
          single_quoted_value
        when '`'
          @stack << :tick_value
        when '/'
          if match_index = @source.rindex(/(\w+|\)|\])\s*\//, @index)
            match = @source.match(/(\w+|\)|\])\s*\//, match_index)
            if match[0].length + match_index != @index
              regex_value
            end
          else
            regex_value
          end
        when '('
          @stack.push :parenthesis
        when ')'
          raise unexptected_token(")") if @stack.last != :parenthesis
          @stack.pop
        when '{'
          @stack.push :brackets
        when '}'
          case @stack.last
          when :brackets, :tick_statment
            @stack.pop
          else
            raise unexptected_token("}")
          end
        when 'export'
          if @stack.last == :main
            @stack << :export
          end
        when 'import'
          if @stack.last == :main
            @stack << :import
          end
        else
          @stack.pop
        end
      end

      if last_postion == @index
        syntax_error = Condenser::SyntaxError.new("Error parsing JS file with JSAnalyzer")
        syntax_error.instance_variable_set(:@path, @sourcefile)
        raise Condenser::SyntaxError, "Error parsing JS file with JSAnalyzer"
      else
        last_postion = @index
      end
    end
  end
  
  def unexptected_token(token)
    start = (@source.rindex("\n", @old_index) || 0) + 1
    uptop = @source.index("\n", @index) || (@old_index + @matched.length)
    lineno = @source[0..start].count("\n") + 1

    message = "Unexpected token #{token} #{@sourcefile} #{lineno.to_s.rjust(4)}:#{(@index-start)}"
    message << "\n#{lineno.to_s.rjust(4)}: " << @source[start..uptop]
    message << "\n      #{'-'* (@index-1-start)}#{'^'*(@matched.length)}"
    message << "\n"
    
    syntax_error = Condenser::SyntaxError.new(message)
    syntax_error.instance_variable_set(:@path, @sourcefile)
    syntax_error
  end
  
  def double_quoted_value
    ret_value = ""

    while scan_until(/[\"\n]/)
      if matched == "\n"
        raise unexptected_token("\\n")
      elsif matched == "\""
        if pre_match[-1] != "\\"
          ret_value << pre_match
          return ret_value
        else
          ret_value << pre_match << "\\\""
        end

        
      else
        ret_value << match
      end
    end
  end
  
  def single_quoted_value
    ret_value = ""

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
    ret_value = ""

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
    ret_value = ""

    while scan_until(/\//)
      if matched == "/" && pre_match[-1] != "\\"
        ret_value << pre_match
        return ret_value
      else
        ret_value << pre_match
      end
    end
  end

end