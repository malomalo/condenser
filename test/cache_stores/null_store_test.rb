require 'test_helper'

class CacheNullStoreTest < ActiveSupport::TestCase

  def setup
    super
    @store = Condenser::Cache::NullStore.new
    @env.cache = @store
  end

  def new_env
    env = Condenser.new(@path, logger: Logger.new('/dev/null', level: :debug), npm_path: @npm_dir, base: @path, cache: @store)
    env.unregister_writer(Condenser::ZlibWriter)
    env.unregister_writer(Condenser::BrotliWriter)
    env
  end

  test 'processing and exporting a JS and a CSS asset' do
    file 'main.js', "console.log(1 + 2);\n"
    file 'main.css', "body { color: red; }\n"

    assert_file 'main.js', 'application/javascript'
    assert_file 'main.css', 'text/css'
    assert_includes assert_exported_file('main.js', 'application/javascript').source, 'console.log'
    assert_includes assert_exported_file('main.css', 'text/css').source, 'color'
  end

  test 'nothing is cached between environments' do
    file 'main.js.erb', "console.log(<%= 1 + 2 %>);\n"
    file 'main.css.erb', "body { width: <%= 1 + 2 %>px; }\n"

    # Count ERB renders; each environment should render both assets again.
    erb = Condenser::Erubi.instance_method(:call)
    renders = 0
    Condenser::Erubi.define_method(:call) { |*args| renders += 1; erb.bind_call(self, *args) }

    2.times do
      @env = new_env
      assert_includes assert_exported_file('main.js', 'application/javascript').source, '3'
      assert_includes assert_exported_file('main.css', 'text/css').source, '3px'
    end
    assert_equal 4, renders
  ensure
    Condenser::Erubi.define_method(:call, erb) if erb
  end

  test 'fetch and fetch_if always run the block and store nothing' do
    assert_equal 1, @store.fetch('key') { 1 }
    assert_equal 2, @store.fetch('key') { 2 }
    assert_equal 3, @store.fetch('key', force: true) { 3 }

    key_proc = Proc.new { 'value-key' }
    assert_equal 4, @store.fetch_if(key_proc, 'deps-key') { 4 }
    assert_equal 5, @store.fetch_if(key_proc, 'deps-key') { 5 }
    assert_equal 6, @store.fetch_if('value-key', 'deps-key') { 6 }

    assert_nil @store.get('key')
    assert_nil @store.get('value-key')
    assert_equal 7, @store.set('key', 7)
    assert_nil @store.get('key')
    assert_equal false, @store.delete('key')
    assert_equal true, @store.clear
  end

end
