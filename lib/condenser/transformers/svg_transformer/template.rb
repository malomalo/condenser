# frozen_string_literal: true

class Condenser::SVGTransformer::Template
  
  include Condenser::ParseHelpers

  attr_accessor :source

  START_TAGS = ['<']
  CLOSE_TAGS = ['/>', '>']
  VOID_ELEMENTS = ['!DOCTYPE', '?xml']
  
  def initialize(source)
    @source = source.strip
    process
  end

  def process
    seek(0)
    @tree =   [Condenser::SVGTransformer::Base.new]
    @stack =  [:str]
    
    while !eos?
      case @stack.last
      when :str
        scan_until(Regexp.new("(#{START_TAGS.map{|s| Regexp.escape(s) }.join('|')}|\\z)"))
        if !matched.nil? && START_TAGS.include?(matched)
          @stack << :tag
        end
      when :tag
        scan_until(Regexp.new("(\\/|[^\\s>]+)"))
        if matched == '/'
          @stack.pop
          @stack << :close_tag
        else
          @tree << Condenser::SVGTransformer::Tag.new(matched)
          @stack << :tag_attr_key
        end
      when :close_tag
        scan_until(Regexp.new("([^\\s>]+)"))

        el = @tree.pop
        if el.tag_name != matched
          raise Condenser::SVGTransformer::TemplateError.new("Expected to close #{el.tag_name.inspect} tag, instead closed #{matched.inspect}\n#{cursor}")
        end
        if !['!DOCTYPE', '?xml'].include?(el.tag_name)
          @tree.last.children << el
          scan_until(Regexp.new("(#{CLOSE_TAGS.map{|s| Regexp.escape(s) }.join('|')})"))
          @stack.pop
        end
      when :tag_attr_key
        scan_until(Regexp.new("(#{CLOSE_TAGS.map{|s| Regexp.escape(s) }.join('|')}|[^\\s=>]+)"))
        if CLOSE_TAGS.include?(matched)
          if matched == '/>' || VOID_ELEMENTS.include?(@tree.last.tag_name)
            el = @tree.pop
            @tree.last.children << el
            @stack.pop
            @stack.pop
          else
            @stack << :str
          end
        else
          key = if matched.start_with?('"') && matched.end_with?('"')
            matched[1..-2]
          elsif matched.start_with?('"') && matched.end_with?('"')
            matched[1..-2]
          else
            matched
          end
          @tree.last.attrs << key
          @stack << :tag_attr_value_tx
        end
      when :tag_attr_value_tx
        scan_until(Regexp.new("(#{(CLOSE_TAGS).map{|s| Regexp.escape(s) }.join('|')}|=|\\S)"))
        tag_key = @tree.last.attrs.pop
        if CLOSE_TAGS.include?(matched)
          el = @tree.last
          el.attrs << tag_key
          if VOID_ELEMENTS.include?(el.tag_name)
            @tree.pop
            @tree.last.children << el
          end
          @stack.pop
          @stack.pop
          @stack.pop
        elsif matched == '='
          @stack.pop
          @tree.last.attrs << tag_key
          @stack << :tag_attr_value
        else
          @stack.pop
          @tree.last.attrs << tag_key
          rewind(1)
        end

      when :tag_attr_value
        scan_until(Regexp.new("(#{CLOSE_TAGS.map{|s| Regexp.escape(s) }.join('|')}|'|\"|\\S+)"))

        if matched == '"'
          @stack.pop
          @stack << :tag_attr_value_double_quoted
        elsif matched == "'"
          @stack.pop
          @stack << :tag_attr_value_single_quoted
        else
          @stack.pop
          key = @tree.last.attrs.pop
          @tree.last.namespace = matched if key == 'xmlns'
          @tree.last.attrs << { key => matched }
        end
      when :tag_attr_value_double_quoted
        quoted_value = String.new
        scan_until(/"/)
        quoted_value << pre_match if !pre_match.strip.empty?
        rewind(1)

        quoted_value = Condenser::SVGTransformer::Value.new(quoted_value)

        key = @tree.last.attrs.pop
        @tree.last.namespace = quoted_value if key == 'xmlns'
        if @tree.last.attrs.last.is_a?(Hash) && !@tree.last.attrs.last.has_key?(key)
          @tree.last.attrs.last[key] = quoted_value
        else
          @tree.last.attrs << { key => quoted_value }
        end
        scan_until(/\"/)
        @stack.pop
      when :tag_attr_value_single_quoted
        quoted_value = ''
        scan_until(/(')/)
        quoted_value << pre_match if !pre_match.strip.empty?
        rewind(1)

        quoted_value = Condenser::SVGTransformer::Value.new(quoted_value)

        key = @tree.last.attrs.pop
        @tree.last.namespace = quoted_value if key == 'xmlns'
        if @tree.last.attrs.last.is_a?(Hash) && !@tree.last.attrs.last.has_key?(key)
          @tree.last.attrs.last[key] = quoted_value
        else
          @tree.last.attrs << { key => quoted_value }
        end
        scan_until(/\'/)
        @stack.pop
      end
    end
  end

  def to_module
    @tree.first.to_module
  end

end