require 'rspec/core/rake_task'
require 'rubygems/package_task'

gemspec = eval(IO.read('hosted-chef.gemspec'))
Gem::PackageTask.new(gemspec).define

desc "Run all specs in spec directory"
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = FileList['integration/**/*_spec.rb']
end

