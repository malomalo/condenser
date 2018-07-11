require 'ejs'

class Condenser
  class EjsTransformer
    
    def self.call(environment, data)
      data[:source] = ::EJS.transform(data[:source])
    end
    
  end
end