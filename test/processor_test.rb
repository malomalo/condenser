require 'test_helper'

class ProcessorTest < ActiveSupport::TestCase

  # Records its setups and calls, in order, in +events+.
  class RecordingProcessor < Condenser::Processor
    attr_reader :events

    def initialize(events = [])
      @events = events
    end

    def setup(environment)
      @events << [:setup, environment]
    end

    def call(environment, input)
      @events << [:call, input[:filename]]
    end
  end

  def new_env(cache: Condenser::Cache::MemoryStore.new)
    Condenser.new(@path, logger: Logger.new('/dev/null'), npm_path: @npm_dir, base: @path, cache: cache)
  end

  test 'the defaults' do
    processor = Condenser::Processor.new
    assert_nil processor.setup(@env)
    assert_equal({}, processor.options)
    assert_equal 'Condenser::Processor', processor.name

    error = assert_raises(NotImplementedError) { processor.call(@env, {}) }
    assert_equal "Condenser::Processor#call isn't implemented", error.message
  end

  test 'registering a class or an object that is not a processor raises' do
    error = assert_raises(ArgumentError) { @env.register_minifier('text/css', Condenser::SassMinifier) }
    assert_equal "Condenser::SassMinifier isn't a Condenser::Processor instance (register Condenser::SassMinifier.new)", error.message

    callable = ->(environment, input) { }
    [
      -> (e) { @env.register_template('application/erb', e) },
      -> (e) { @env.register_preprocessor('text/css', e) },
      -> (e) { @env.register_transformer('text/scss', 'text/css', e) },
      -> (e) { @env.register_postprocessor('text/css', e) },
      -> (e) { @env.register_exporter('text/css', e) },
      -> (e) { @env.register_minifier('text/css', e) }
    ].each do |register|
      assert_raises(ArgumentError) { register.call(RecordingProcessor) }
      assert_raises(ArgumentError) { register.call(callable) }
    end
  end

  test 'a processor that only defines call works' do
    upcase = Class.new(Condenser::Processor) do
      def call(environment, input)
        input[:source] = input[:source].upcase
      end
    end
    @env.register_postprocessor('text/plain', upcase.new)
    file 'test.txt', 'hello'

    assert_equal 'HELLO', @env.find('test.txt').source
  end

  test 'a processor is set up once per environment, with it, before its first call' do
    processor = RecordingProcessor.new
    file 'a.txt', 'a'
    file 'b.txt', 'b'

    env1 = new_env
    env1.register_preprocessor('text/plain', processor)
    env1.find('a.txt').process
    env1.find('b.txt').process

    env2 = new_env
    env2.register_preprocessor('text/plain', processor)
    env2.find('a.txt').process

    assert_equal [[:setup, env1], [:call, 'a.txt'], [:call, 'b.txt'], [:setup, env2], [:call, 'a.txt']], processor.events
  end

  test 'a processor is set up on a warm build that reads the cache without calling it' do
    file 'a.txt', 'a'
    cache = Condenser::Cache::MemoryStore.new

    cold = RecordingProcessor.new
    env = new_env(cache: cache)
    env.register_preprocessor('text/plain', cold)
    env.find('a.txt').export
    assert_equal [[:setup, env], [:call, 'a.txt']], cold.events

    warm = RecordingProcessor.new
    env = new_env(cache: cache)
    env.register_preprocessor('text/plain', warm)
    env.find('a.txt').export
    assert_equal [[:setup, env]], warm.events
  end

  test 'exporters and minifiers are set up before their first call' do
    events = []
    exporter = RecordingProcessor.new(events)
    minifier = RecordingProcessor.new(events)
    @env.register_exporter('text/plain', exporter)
    @env.register_minifier('text/plain', minifier)
    file 'a.txt', 'a'
    file 'b.txt', 'b'

    @env.find('a.txt').export
    @env.find('b.txt').export

    assert_equal [
      [:setup, @env], [:setup, @env],
      [:call, 'a.txt'], [:call, 'a.txt'],
      [:call, 'b.txt'], [:call, 'b.txt']
    ], events
  end

  test 'a processor registered for a type no asset uses is never set up' do
    processor = RecordingProcessor.new
    @env.register_preprocessor('text/x-unused', processor)
    @env.register_exporter('text/x-unused', processor)
    file 'a.txt', 'a'

    @env.find('a.txt').export
    assert_empty processor.events
  end

  test 'the built-in processors are instances that keep no state between calls' do
    analyzer = @env.preprocessors['application/javascript'].first
    assert_instance_of Condenser::JSAnalyzer, analyzer
    file 'main.js', "import a from './a';\nexport default a;\n"
    file 'a.js', "export default 1;\n"
    @env.find('main.js').process
    assert_empty analyzer.instance_variables

    combiner = Condenser::CSSMediaCombinerProcessor.new
    @env.register_postprocessor('text/css', combiner)
    @env.unregister_minifier('text/css')
    file 'main.css', "@media (min-width: 1px) { .a { color: red; } }\n"
    @env.find('main.css').process
    assert_empty combiner.instance_variables

    %i[templates transformers].each do |kind|
      Condenser.send(kind).each_value do |processors|
        Array(processors.is_a?(Hash) ? processors.values : processors).each do |processor|
          assert_kind_of Condenser::Processor, processor
        end
      end
    end
  end

end
