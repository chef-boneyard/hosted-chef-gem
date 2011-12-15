require 'pp'
require 'forwardable'
require 'optparse'
require 'rexml/document'

require 'rubygems'
require 'restclient'
require 'highline'


module HostedChef

  class InvalidPassword < RuntimeError
  end

  class Options
    attr_writer :password

    def password
      @password ||= HighLine.new.ask("Your Hosted Chef password: ") {|q| q.echo = "*"}
    end

    attr_writer :username

    def username
      @username ||= HighLine.new.ask("Your Hosted Chef username? ")
    end

    attr_writer :orgname

    def orgname
      @orgname ||= HighLine.new.ask("Your Hosted Chef organization? ")
    end

    # force evaluation of options
    def ask_for_missing_opts
      username
      password
      orgname
    end

  end

  class ConfigValidator

    extend Forwardable

    def_delegators :@options, :username, :password, :orgname

    def initialize(api_client, options)
      @api_client, @options = api_client, options
    end

    def validate!
      puts "Validating your account information..."
      validate_username
      validate_password
      validate_orgname
    end

    def validate_username
      RestClient.head("http://community.opscode.com/users/#{username}")
      puts "* Username '#{username}' is valid."
    rescue RestClient::ResourceNotFound
      STDERR.puts "The user '#{username}' does not exist. Check your spelling, or visit http://www.opscode.com/hosted-chef/ to sign up."
      exit 1
    end

    def validate_password
      @api_client.login_cookies
      puts "* Password is correct"
    rescue InvalidPassword
      STDERR.puts "Could not login with the password you gave. Check your "\
        "typing, or visit http://community.opscode.com/password_reset_requests/new"\
        " to reset your password."
      exit 1
    end

    def validate_orgname
      page = RestClient.get("https://manage.opscode.com/organizations/#{orgname}", :cookies => @api_client.login_cookies)
      # TODO: use actual HTTP response codes.
      if page =~ /not found/i
        STDERR.puts "The organization '#{orgname}' does not exist. Check your"\
          " spelling, or visit https://manage.opscode.com/organizations to create your organization"
        exit 1
      elsif page =~ /permission denied/i
        STDERR.puts "You are not associated with the organization '#{orgname}'"\
          " or you do not have sufficient privileges to download its validator"\
          " key. Ask an administrator of this org to invite you."
        exit 1
      end
      puts "* Organization name '#{orgname}' is correct"
    end
  end

  class ArgvParser

    attr_reader :options

    def initialize(argv)
      @options = Options.new
      @argv = argv
    end

    def parse
      parser.parse!
      options.ask_for_missing_opts
      options
    end

    def parser
      OptionParser.new do |o|
        o.on("-u", "--user USERNAME", "Your Hosted Chef username") do |username|
          options.username = username
        end

        o.on("-p", "--password PASSWORD", "Your Hosted Chef password") do |passwd|
          options.password = passwd
        end

        o.on('-o', "--organization ORGANIZATION", "Your Hosted Chef Organization") do |orgname|
          options.orgname = orgname
        end

        o.on('-h', "--help") do
          puts o
          exit 1
        end
      end
    end

  end

  #--
  # Someday we'll return JSON when you ask for it, and then the naming of this
  # class won't be a passive aggressive joke.
  class ApiClient

    extend Forwardable

    def_delegators :@options, :username, :password, :orgname

    def initialize(options)
      @options = options
    end

    def login_authenticity_token
      @auth_token ||= begin
        login_page = RestClient.get('https://manage.opscode.com')
        extract_csrf_token_from(login_page)
      end
    end

    def user_key_authenticity_token
      @user_key_authenticity_token ||= begin
        new_key_page = RestClient.get("https://community.opscode.com/users/#{username}/user_key/new", :cookies => login_cookies)
        extract_csrf_token_from(new_key_page)
      end
    end

    def login_cookies
      @login_cookies ||= begin
        post_options = {:name => username,
                        :password => password,
                        :authenticity_token => login_authenticity_token,
                        :multipart => true}

        RestClient.post("https://manage.opscode.com/login_exec", post_options) do |response, req, result, &block|
          if response.headers[:location] == "https://manage.opscode.com/login" # bad passwd
            raise InvalidPassword
          else
            response.cookies
          end
        end
      end
    end

    def knife_config
      RestClient.get("https://manage.opscode.com/organizations/#{orgname}/_knife_config", :cookies => login_cookies)
    end

    def user_key
      post_options = {
        :authenticity_token => user_key_authenticity_token,
        :multipart => true
      }
      RestClient.post("https://community.opscode.com/users/#{username}/user_key", post_options, {:cookies => login_cookies})
    end

    private

    def extract_csrf_token_from(page)
      # TODO: serve the authenticity token over JSON so we don't have to
      # do this.
      md = page.match(/(<input[^\>]*name=\"authenticity_token\"[^\>]+\>)/)
      page_element = md[1]
      xml = REXML::Document.new(page_element)
      xml.elements.first.attributes["value"]
    end
  end

  class ConfigInstaller
    def initialize(api_client)
      @api_client = api_client
    end

    def install_dir
      home_dot_chef = File.expand_path("~/.chef")
      cwd_dot_chef  = File.expand_path(".chef")

      if ENV['USER'] && !File.exist?(home_dot_chef)
        home_dot_chef
      elsif !File.exist(cwd_dot_chef)
      else
      end
    end
  end

  class Controller

    attr_reader :argv

    def initialize(argv=ARGV)
      @argv = argv
    end

    def greeting
      puts(<<-WELCOME)
## WELCOME! ##
Welcome to Opscode Hosted Chef. We're going to download your API keys and knife
config from Opscode and install them on your system.

Before you continue, please be aware that this program will update your API key
and your organization's validation key. The existing keys for these accounts
will be expired and no longer valid.

WELCOME

      unless HighLine.new.agree("Ready to get started? (yes/no): ")
        STDERR.puts "goodbye."
        exit 1
      end
    end

    def setup_and_validate
      @options = ArgvParser.new(argv).parse
      @api_client = ApiClient.new(@options)
      @validator = ConfigValidator.new(@api_client, @options)
      @validator.validate!
    end

    def fetch_and_install
      puts "knife config: "
      puts @api_client.knife_config
      puts ""
      puts "user key:"
      puts @api_client.user_key
    end

    def goodbye
      puts(<<-RESOURCES)

You're ready to go! To verify your configuration, try running
`knife client list`

If you should run into trouble check the following resources:
* Knife built-in manuals: run `knife help`
* Documentation at http://wiki.opscode.com
* Get support from Opscode: http://help.opscode.com/
RESOURCES
    end


    def run
      greeting
      setup_and_validate
      fetch_and_install
      goodbye
    end

  end
end

HostedChef::Controller.new.run



