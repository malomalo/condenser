require 'test_helper'
require 'rake/condensertask'

class RakeTaskTest < ActiveSupport::TestCase

  def setup
    super
    @dir = Dir.mktmpdir
    @rake = Rake::Application.new
    Rake.application = @rake
  end

  def teardown
    super
    FileUtils.remove_entry(@dir, true)
  end

  test "the manifest logs to the task's logger" do
    file 'application.js', "console.log(1);\n"
    log = StringIO.new
    task = Rake::CondenserTask.new do |t|
      t.environment = @env
      t.output = @dir
      t.assets = %w(application.js)
      t.logger = Logger.new(log)
    end

    @rake['assets'].invoke
    @rake['clobber_assets'].invoke

    assert_match(/Removed #{Regexp.escape(File.join(@dir, 'manifest.json'))}/, log.string)
  end

  test "clean_assets removes files that aren't in the manifest" do
    file 'application.js', "console.log(1);\n"
    Rake::CondenserTask.new do |t|
      t.environment = @env
      t.output = @dir
      t.assets = %w(application.js)
      t.logger = Logger.new(File::NULL)
    end

    @rake['assets'].invoke
    File.write(File.join(@dir, 'old-abc.js'), 'old')
    @rake['clean_assets'].invoke

    assert_not File.exist?(File.join(@dir, 'old-abc.js'))
    assert File.exist?(File.join(@dir, @env.find('application.js').export.path))
  end

end
