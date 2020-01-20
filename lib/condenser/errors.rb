# Basic Condenser error classes
class Condenser
  class Error < StandardError; end
  class SyntaxError < ::SyntaxError; end
  class CommandNotFoundError < Error; end
  # class ArgumentError           < Error; end
  class ContentTypeMismatch     < Error; end
  # class NotImplementedError     < Error; end
  class NotFound                < Error; end
  # class ConversionError         < NotFound; end
  class FileNotFound            < NotFound; end
  # class FileOutsidePaths        < NotFound; end
end
