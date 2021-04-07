class Condenser::CSSMediaCombinerProcessor < Condenser::NodeProcessor
  
  def call(environment, input)
    buffer = ""
    query_flag = false
    media_queries = {}
    input[:source].split(/(@media)/).each do |result|
      if query_flag
        query, rules = result.split("{", 2)
        
        rules_buffer = ""
        bracket_count = 1
        rules.each_char do |char|
          if query_flag && char == "{"
            bracket_count += 1
          elsif query_flag && char == "}"
            bracket_count -= 1
            if bracket_count == 0
              media_queries[query.strip] ||= ""
              media_queries[query.strip] += rules_buffer
              rules_buffer = ""
              query_flag = false
              next
            end
          end
          
          rules_buffer += char
        end
        
        buffer += rules_buffer
        query_flag = false
      elsif result == "@media"
        query_flag = true
      else
        buffer += result
      end
    end
    
    media_queries.each do |query, query_buffer|
      buffer += "@media #{query} {#{query_buffer}}"
    end
    
    input[:source] = buffer
  end

end