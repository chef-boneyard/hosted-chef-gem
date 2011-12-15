class IntegrationConfig < Struct.new(:user, :org, :password)
  def credentials
    yield self
  end
end

CONFIG = IntegrationConfig.new
config_path = File.expand_path('../creds.rb', __FILE__)
unless File.exist?(config_path)
  STDERR.puts(<<-CONFIGURE_ME)
* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
No credentials are configured for integration tests. To run the
integration tests:

0. Create a Hosted Chef account for running these tests.
1. cp integration/creds.rb.example integration/creds.rb
2. Edit integration/creds.rb to configure your username/orgname/password

* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
CONFIGURE_ME
  exit! 1
end

CONFIG.instance_eval(IO.read(config_path))

