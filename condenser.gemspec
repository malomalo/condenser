require File.expand_path("../lib/condenser/version", __FILE__)

Gem::Specification.new do |s|
  s.name          = 'condenser'
  s.version       = Condenser::VERSION
  s.authors       = ["Jon Bracy"]
  s.email         = ["jonbracy@gmail.com"]
  s.homepage      = "https://github.com/malomalo/condenser"
  s.summary       = 'A Rack-based asset packaging system'
  s.description   = "Condenser is a Rack-based asset packaging system that concatenates and serves JavaScript, CSS, Sass, and SCSS."  
  s.license       = "MIT"

  s.extra_rdoc_files = %w(README.md)
  s.rdoc_options.concat ['--main', 'README.md']

  s.files         = `git ls-files -- README.md CHANGELOG.md LICENSE {lib,ext}/*`.split("\n")
  s.test_files    = `git ls-files -- test/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = %w(lib)
  
  s.required_ruby_version = '>= 2.4.0'

  s.add_runtime_dependency  "ruby-ejs", '~> 1.0'  
  s.add_runtime_dependency  "erubi", '~> 1.0'
  s.add_runtime_dependency  "rack",  '> 1', '< 3'

  s.add_development_dependency 'activesupport'
  s.add_development_dependency "sassc", ">= 2.2.0", "< 3.0"
  s.add_development_dependency "zopfli", "~> 0.0.7"

  # s.add_development_dependency "closure-compiler", "~> 1.1"
  # s.add_development_dependency "coffee-script-source", "~> 1.6"
  # s.add_development_dependency "coffee-script", "~> 2.2"
  # s.add_development_dependency "eco", "~> 1.0"
  # s.add_development_dependency "ejs", "~> 1.0"
  # s.add_development_dependency "execjs", "~> 2.0"
  # s.add_development_dependency "minitest", "~> 5.0"
  # s.add_development_dependency "nokogiri", "~> 1.3"
  # s.add_development_dependency "rack-test", "~> 0.6"
  # s.add_development_dependency "rake", "~> 10.0"
  # s.add_development_dependency "uglifier", ">= 2.3"
  # s.add_development_dependency "yui-compressor", "~> 0.12"
end

