require 'test_helper'

class NpmInstallTest < ActiveSupport::TestCase

  test 'processes installing into the same empty npm path at once get every package' do
    npm = File.realpath(Dir.mktmpdir)
    packages = %w[picocolors detect-libc]

    # The children wait on the pipe so they all start installing together
    start, go = IO.pipe
    pids = 6.times.map do |i|
      fork do
        go.close
        start.read
        Condenser::NodeProcessor.new(npm).npm_install(packages[i % 2])
        exit!(0)
      end
    end
    start.close
    go.close
    pids.each { |pid| Process.wait(pid) }

    packages.each do |package|
      assert system('node', '-e', "require.resolve(#{package.to_json})", chdir: npm, err: File::NULL), "#{package} isn't installed"
    end
    assert_equal packages.sort, JSON.parse(File.read(File.join(npm, 'package.json')))['dependencies'].keys.sort
  ensure
    FileUtils.remove_entry(npm, true) if npm
  end

  test 'a name@range installs that range' do
    npm = File.realpath(Dir.mktmpdir)

    Condenser::NodeProcessor.new(npm).npm_install('picocolors@^0.2')
    Condenser::NodeProcessor.new(npm).npm_install('@tootallnate/once@^1')

    assert_equal '0.2', installed_version(npm, 'picocolors')[/\A\d+\.\d+/]
    assert_equal '1', installed_version(npm, '@tootallnate/once').split('.')[0]
  ensure
    FileUtils.remove_entry(npm, true) if npm
  end

  test 'a name@range that is installed at another version is kept' do
    npm = File.realpath(Dir.mktmpdir)
    %w[picocolors @fake/package].each do |name|
      FileUtils.mkdir_p(File.join(npm, 'node_modules', name))
      File.write(File.join(npm, 'node_modules', name, 'package.json'), JSON.generate({ name: name, version: '9.0.0' }))
    end

    Condenser::NodeProcessor.new(npm).npm_install('picocolors@^0.2', '@fake/package@^1', '@fake/package')

    assert_equal '9.0.0', installed_version(npm, 'picocolors')
    assert_equal '9.0.0', installed_version(npm, '@fake/package')
    assert_not File.exist?(File.join(npm, 'package.json'))
  ensure
    FileUtils.remove_entry(npm, true) if npm
  end

  def installed_version(npm, name)
    JSON.parse(File.read(File.join(npm, 'node_modules', name, 'package.json')))['version']
  end

  test 'installs into the npm path, not a parent directory with a package.json' do
    parent = File.realpath(Dir.mktmpdir)
    File.write(File.join(parent, 'package.json'), "{}\n")
    npm = File.join(parent, 'npm')

    Condenser::NodeProcessor.new(npm).npm_install('picocolors')

    assert Dir.exist?(File.join(npm, 'node_modules', 'picocolors'))
    assert_not Dir.exist?(File.join(parent, 'node_modules'))
    assert_equal "{}\n", File.read(File.join(parent, 'package.json'))
  ensure
    FileUtils.remove_entry(parent, true) if parent
  end

end
