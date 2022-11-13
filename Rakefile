# require 'bundler/setup'
# require "bundler/gem_tasks"
# Bundler.require(:development)

require 'fileutils'
require "rake/testtask"
require "rubygems/package_task"

# Test Task
Rake::TestTask.new do |t|
    t.libs << 'lib' << 'test'
    t.test_files = FileList[ARGV[1] ? ARGV[1] : 'test/**/*_test.rb']
    t.warning = true
    t.verbose = true
end

spec = Gem::Specification.load("condenser.gemspec")

Gem::PackageTask.new(spec) do |pkg|
#   pkg.need_zip = true
#   pkg.need_tar = true
end
