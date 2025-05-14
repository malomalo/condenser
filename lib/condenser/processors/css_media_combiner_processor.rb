# frozen_string_literal: true

class Condenser::CSSMediaCombinerProcessor
  
  include Condenser::ParseHelpers
  
  def self.setup(env)
  end
  
  def self.call(environment, input)
    new.call(environment, input)
  end

  def reduce_media_query(queries)
    output = String.new
    queries.each do |query, contents|
      output << query if query
      output << if contents.is_a?(Hash)
        reduce_media_query(contents)
      else
        contents + '}'
      end
    end
    output
  end
  
  def call(environment, input)
    seek(0)
    @sourcefile = input[:source_file]
    @source = input[:source]
    @stack =  []
    @selectors = []
    @media_queries = {}

    input[:source] = String.new
    while !eos?
      output = if @selectors.empty?
        input[:source]
      else
        (@selectors[0...-1].reduce(@media_queries) { |hash, selector| hash[selector] ||= {} }[@selectors.last] ||= String.new)
      end
      
      case @stack.last
      when :media_query
        scan_until(/(@media[^\{]*{|\{|\})/)
        case matched
        when '{'
          output << pre_match << matched
          @stack << :statement
        when '}'
          output << pre_match
          @stack.pop
          @selectors.pop
        else
          output << pre_match
          @selectors << matched.squish
          @stack << :media_query
        end
      when :statement
        scan_until(/(\{|\})/)
        output << pre_match << matched
        case matched
        when '{'
          @stack << :statement
        when '}'
          @stack.pop
        end
      else
        case scan_until(/(@media[^\{]*{|\Z)/)
        when ''
          output << pre_match
        else
          output << pre_match
          @selectors << matched.squish
          @stack << :media_query
        end
      end
    end

    input[:source] << reduce_media_query(@media_queries)
  end

end