require 'test_helper'
require 'lightningcss'

class LightningCSSProcessorTest < ActiveSupport::TestCase

  class Processor
    include Condenser::LightningCSSProcessor

    RESERVED_OPTIONS = Condenser::LightningCSSProcessor::RESERVED_OPTIONS.merge(scope: 'not here').freeze
    DEFAULT_OPTIONS = { error_recovery: false }.freeze
    FORCED_OPTIONS = { minify: true }.freeze
  end

  def setup
    super
    @backend = LightningCSS::Backend
  end

  test "doesn't shadow the lightningcss gem inside Condenser" do
    assert_not Condenser.const_defined?(:LightningCSS, false)
  end

  test 'extends the including class with its class methods' do
    assert_nil Processor.setup(@env)
    assert_equal LightningCSS::VERSION, Processor.version
  end

  test 'builds the options from the including class constants' do
    processor = Processor.new(targets: { safari: 12, chrome: 80 }, error_recovery: true)

    assert_equal 'LightningCSSProcessorTest::Processor', processor.name
    assert_equal [:error_recovery, :targets, :minify, :lightningcss], processor.options.keys
    assert_equal({ error_recovery: true, targets: { 'chrome' => 80, 'safari' => 12 }, minify: true, lightningcss: LightningCSS::VERSION }, processor.options)
    assert processor.options.frozen?
  end

  test "raises for the including class's reserved options" do
    error = assert_raises(ArgumentError) { Processor.new(scope: 'x') }
    assert_equal "Processor options can't include :scope, not here", error.message
    assert_raises(ArgumentError) { Processor.new(filename: 'x.css') }
  end

  test 'names the including class when the gem is missing' do
    Processor.stubs(:require).with('lightningcss').raises(LoadError)
    LightningCSS.send(:remove_const, :Backend)

    error = assert_raises(LoadError) { Processor.new }
    assert_equal "LightningCSSProcessorTest::Processor requires the lightningcss gem, add `gem 'lightningcss', '>= 1.33.0.2'` to your Gemfile", error.message
  ensure
    LightningCSS.const_set(:Backend, @backend)
  end

  test 'transforms the input and keeps its helpers private' do
    input = { source: ".a { color: red; }\n", filename: 'test.css' }
    Processor.new.call(@env, input)

    assert_equal '.a{color:red}', input[:source]
    assert_not Processor.new.respond_to?(:located_message)
    assert_not Processor.new.respond_to?(:syntax_error)
  end

end
