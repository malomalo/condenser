require 'test_helper'

class FileWriterTest < ActiveSupport::TestCase

  def setup
    super
    @env.clear_pipeline
    @env.register_writer Condenser::FileWriter.new
  end

  test 'skips a file already in the output directory, not the working directory' do
    file 'index.js', "console.log('hello world!');"
    export = @env.find_export('index.js')

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.dirname(File.join(dir, export.path)))
      File.write(File.join(dir, export.path), 'existing')
      export.write(dir)
      assert_equal 'existing', File.read(File.join(dir, export.path))

      # The working directory having the file doesn't skip writing it
      Dir.mktmpdir do |cwd|
        File.write(File.join(cwd, export.path), 'existing')
        Dir.chdir(cwd) { export.write(File.join(dir, 'new')) }
      end
      assert_equal export.source, File.read(File.join(dir, 'new', export.path))
    end
  end

end
