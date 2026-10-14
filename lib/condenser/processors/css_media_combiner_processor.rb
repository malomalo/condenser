# frozen_string_literal: true

# TODO: See if this is still needed now that Condenser::LightningCSSExporter
# can minify CSS. Moving every @media block to the end of the file can change
# which rule wins:
#
#     .a { color: red; }
#     @media (max-width: 100px) { .a { color: blue; } }
#     .a { color: green; }
#
# is green at narrow widths, but after combining the @media block comes after
# `.a { color: green; }`, so it's blue. Lightning CSS with `minify: true` only
# merges @media blocks that are next to each other, which keeps the order.
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
        case scan_until(/(@media[^\{]*{|\z)/)
        when ''
          output << pre_match
        else
          output << pre_match.rstrip
          @selectors << matched.squish
          @stack << :media_query
        end
      end
    end

    input[:source] << reduce_media_query(@media_queries)
  end

end