require 'pp'
require 'forwardable'
require 'optparse'
require 'rexml/document'
require 'fileutils'

begin
  require 'rubygems'
rescue LoadError
end

require 'restclient'
require 'highline'

require 'hosted-chef/version'
require 'hosted-chef/api_client'
require 'hosted-chef/cli'
require 'hosted-chef/config_installer'
require 'hosted-chef/controller'


#== HostedChef
# A command line application for interacting with Opscode's Hosted Chef using
# password authentication. The goal of this program is simply to automate tasks
# for which the normal API authentication mechanism cannot be (easily) used.
#
# Developers interested in this code should note that the code is not intended
# for library use. In particular, classes contain methods that call exit or
# request user input.
module HostedChef
end




