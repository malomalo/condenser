# frozen_string_literal: true

# The base class of templates, preprocessors, transformers, postprocessors,
# exporters and minifiers. They're registered as instances:
#
#     class UpcaseProcessor < Condenser::Processor
#       def call(environment, input)
#         input[:source] = input[:source].upcase
#       end
#     end
#
#     env.register_postprocessor 'text/css', UpcaseProcessor.new
#
# An instance can be shared by environments, and called from several threads
# at once, so #call keeps its state in local variables or a new object.
class Condenser::Processor

  # Called once per environment before the processor is first used, and
  # before the cached dependencies of an asset it processes are read. Load
  # optional gems or install npm packages here, so they're only needed when
  # the processor is used.
  def setup(environment)
  end

  # What changes the output besides the source, e.g. the processor's options
  # and the version of the library it uses. It's part of the cache keys.
  def options
    {}
  end

  def name
    self.class.name
  end

  # Processes +input+ (a Hash with the :source, :source_file, :filename,
  # dependencies, ...) in place.
  def call(environment, input)
    raise NotImplementedError, "#{self.class.name}#call isn't implemented"
  end

end
