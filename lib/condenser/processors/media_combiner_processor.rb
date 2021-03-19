require 'css_parser'
require 'json'

class Condenser::MediaCombinerProcessor < Condenser::NodeProcessor
  
  def call(environment, input)
    output = CssParser::Parser.new
    parser = CssParser::Parser.new
    
    parser.load_string!(input[:source])
    
    parser.rules_by_media_query.each do |media_query, rule_sets|
      rule_sets.each do |rule_set|
        output.add_rule_set!(rule_set, media_query)
      end
      
      
    end
    
    input[:source] = output.to_s
  end

end