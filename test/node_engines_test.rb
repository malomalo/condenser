require 'test_helper'

class NodeEnginesTest < ActiveSupport::TestCase

  def setup
    super
    @npm = File.realpath(Dir.mktmpdir)
    @node = Condenser::NodeProcessor.new(@npm)
  end

  def teardown
    FileUtils.remove_entry(@npm, true)
    super
  end

  def package(engines)
    FileUtils.mkdir_p(File.join(@npm, 'node_modules', 'pkg'))
    File.write(File.join(@npm, 'node_modules', 'pkg', 'package.json'), JSON.generate({ name: 'pkg', version: '1.0.0', engines: engines }.compact))
  end

  def satisfies?(range, version)
    package(range && { node: range })
    @node.stubs(:node_version).returns(Gem::Version.new(version))
    @node.check_engines('pkg')
    true
  rescue Condenser::Error
    false
  end

  test 'node_version is the version node reports' do
    assert_equal Gem::Version.new(`#{@node.binary} --version`.strip.delete_prefix('v')), @node.node_version
  end

  test 'check_engines checks the package against engines.node' do
    assert satisfies?(nil, '1.0.0')
    assert satisfies?('^22.18.0 || >=24.11.0', '22.18.0')
    assert satisfies?('^22.18.0 || >=24.11.0', '24.11.0')
    assert satisfies?('^22.18.0 || >=24.11.0', '26.0.0')
    assert_not satisfies?('^22.18.0 || >=24.11.0', '22.17.1')
    assert_not satisfies?('^22.18.0 || >=24.11.0', '23.11.0')
    assert_not satisfies?('^22.18.0 || >=24.11.0', '24.10.0')
    assert satisfies?('>=18 <21', '20.1.0')
    assert_not satisfies?('>=18 <21', '21.0.0')
    assert satisfies?('~20.5.0', '20.5.9')
    assert_not satisfies?('~20.5.0', '20.6.0')
    assert satisfies?('~20.5', '20.5.9')
    assert_not satisfies?('~20.5', '20.6.0')
    assert satisfies?('~20', '20.9.0')
    assert_not satisfies?('~20', '21.0.0')
    assert satisfies?('^22', '22.0.0')
    assert_not satisfies?('^22', '23.0.0')
    assert satisfies?('>6.9.0', '20.0.0')
    assert satisfies?('20.11.1', '20.11.1')
    assert_not satisfies?('<=18', '20.0.0')
  end

  test 'check_engines names the package, range and node' do
    package({ node: '>=99' })
    @node.stubs(:node_version).returns(Gem::Version.new('20.0.0'))
    error = assert_raises(Condenser::Error) { @node.check_engines('pkg') }
    assert_equal "pkg needs Node >=99, but #{@node.binary} is 20.0.0", error.message
  end

  test "check_engines raises for a range it can't read" do
    package({ node: '>= 18.x' })
    error = assert_raises(Condenser::Error) { @node.check_engines('pkg') }
    assert_match(/can't read the Node range/, error.message)
  end

end
