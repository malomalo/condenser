require 'test_helper'

class InspectTest < ActiveSupport::TestCase

  def setup
    super
    file 'foo.js', "console.log(1);\n"
    @export = @env.find('foo.js').export
  end

  # Rails' routing error page prints mounted apps with #inspect, and a large,
  # deeply nested one makes Nokogiri raise "Document tree depth limit
  # exceeded".
  def assert_concise(object)
    inspect = object.inspect
    assert_operator inspect.length, :<, 300, inspect
    assert_operator inspect.count('<'), :<=, 2, inspect
    assert_not_includes inspect, '@mime_types'
    assert_not_includes inspect, '@lookup_cache'
    inspect
  end

  test 'Condenser::Server#inspect is concise' do
    assert_match(/\A#<Condenser::Server #<Condenser paths=1 /, assert_concise(Condenser::Server.new(@env)))
  end

  test 'Condenser#inspect is concise' do
    inspect = assert_concise(@env)
    assert_equal "#<Condenser paths=1 npm_path=#{@npm_dir.inspect} base=#{@path.inspect}>", inspect
  end

  test 'Condenser::BuildCache#inspect is concise' do
    assert_match(/\A#<Condenser::BuildCache listening=(true|false)>\z/, assert_concise(@env.build_cache))
  end

  test 'Condenser::Export#inspect is concise' do
    inspect = assert_concise(@export)
    assert_equal "#<Condenser::Export filename=\"foo.js\" content_types=[\"application/javascript\"] etag=#{@export.etag.inspect}>", inspect
  end

  test 'Condenser::Asset#inspect is concise' do
    assert_includes assert_concise(@env.find('foo.js')), '@filename=foo.js'
  end

end
