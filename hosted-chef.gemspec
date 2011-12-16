$:.unshift(File.dirname(__FILE__) + '/lib')
require 'hosted-chef/version'

Gem::Specification.new do |s|
  s.name = 'hosted-chef'
  s.version = HostedChef::VERSION
  s.platform = Gem::Platform::RUBY
  s.has_rdoc = true
  s.extra_rdoc_files = ["README.md", "LICENSE" ]
  s.summary = "Configures your workstation for Hosted Chef"
  s.description = s.summary
  s.author = "Opscode"
  s.email = "info@opscode.com"
  s.homepage = "http://wiki.opscode.com/"

  s.add_runtime_dependency "rest-client"
  s.add_runtime_dependency "highline"

  %w(rspec).each { |gem| s.add_development_dependency gem }

  s.bindir       = "bin"
  s.executables  = %w[hosted-chef]
  s.require_path = 'lib'
  s.files = %w(LICENSE README.md) + Dir.glob("lib/**/*")
end

