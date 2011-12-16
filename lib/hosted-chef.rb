require 'pp'
require 'forwardable'
require 'optparse'
require 'rexml/document'
require 'fileutils'

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
        @login_cookies = new_key_page.cookies
        extract_csrf_token_from(new_key_page)
      end
    end

    def validator_key_authenticity_token
      @validator_key_authenticity_token ||= begin
        org_list_page = RestClient.get("https://manage.opscode.com/organizations", :cookies => login_cookies)
        @login_cookies = org_list_page.cookies
        extract_csrf_token_from(org_list_page)
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

    def validator_key
      #https://manage.opscode.com/organizations/prodbench2/_regenerate_key
      post_options = {
        #:multipart => true,
        :authenticity_token => validator_key_authenticity_token,
        :_method => "put"
      }
      headers = {
        :Referer => "https://manage.opscode.com/organizations",
        :cookies => login_cookies
      }
      uri = "https://manage.opscode.com/organizations/#{orgname}/_regenerate_key"
      RestClient.post(uri, post_options,headers)
    end
    private

    def extract_csrf_token_from(page)
      # TODO: serve the authenticity token over JSON so we don't have to
      # do this.
      if md = page.match(/(\<meta content=\"[^\"]+\" name=\"csrf-token\"[\s]*\/\>)/)
        page_element = md[1]
        xml = REXML::Document.new(page_element)
        xml.elements.first.attributes["content"]
      elsif md = page.match(/(<input[^\>]*name=\"authenticity_token\"[^\>]+\>)/)
        page_element = md[1]
        xml = REXML::Document.new(page_element)
        xml.elements.first.attributes["value"]
      else
        raise "Can't find CSRF token on the page:\n#{page}"
      end
    end
  end

  class ConfigInstaller
    attr_reader :install_type

    def initialize(api_client, options)
      @api_client, @options = api_client, options
      @install_dir, @install_type = nil, nil
    end

    def validate!
      install_dir
    end

    def install_dir
      unless @install_dir
        @install_dir, @install_type = select_install_dir
      end
      @install_dir
    end

    def install_all
      puts "\nInstalling..."

      puts "> mkdir -p #{install_dir}"
      FileUtils.mkdir_p(install_dir)

      knife_rb = "#{@install_dir}/knife.rb"
      puts "> create #{knife_rb} 0644"
      File.open(knife_rb, File::RDWR|File::CREAT, 0644) {|f|
        f << @api_client.knife_config
      }

      user_pem = "#{@install_dir}/#{@options.username}.pem"
      puts "> create #{user_pem} 0600"
      File.open(user_pem, File::RDWR|File::CREAT, 0600) {|f|
        f << @api_client.user_key
      }

      validator_pem = "#{@install_dir}/#{@options.orgname}-validator.pem"
      puts "> create #{validator_pem} 0600"
      File.open(validator_pem, File::RDWR|File::CREAT, 0600) {|f|
        f << @api_client.validator_key
      }
    end

    private

    def select_install_dir
      home_dot_chef = File.expand_path("~/.chef")
      cwd_dot_chef  = File.expand_path(".chef")

      if ENV['USER'] && !File.exist?(home_dot_chef)
        [home_dot_chef, :default]
      elsif !File.exist?(cwd_dot_chef)
        [cwd_dot_chef, :non_default]
      else
        install_locations = [home_dot_chef, cwd_dot_chef].uniq
        if install_locations.size == 1
          STDERR.puts(<<-NOWHERE_TO_GO)
ERROR: You already have a Chef configuration in your home directory
(#{home_dot_chef})

If you really want to replace this configuration, you can remove it,
otherwise cd to a different directory to generate a new config.
NOWHERE_TO_GO
        else
          STDERR.puts(<<-NOWHERE_TO_GO)
ERROR: You already have a Chef configuration in your home directory and
your current working directory.
(#{home_dot_chef} and #{cwd_dot_chef})

If you wish to replace one of these you can remove it, otherwise you can
cd to a different directory to create a new config.
NOWHERE_TO_GO
          exit 1
        end
      end
    end
  end

  class Controller

    attr_reader :argv

    def initialize(argv=ARGV)
      @argv = argv
      @options = ArgvParser.new(argv).parse
      @api_client = ApiClient.new(@options)
      @validator = ConfigValidator.new(@api_client, @options)
      @config_installer = ConfigInstaller.new(@api_client, @options)
    end

    def greeting
      puts(<<-WELCOME)
Welcome to Opscode Hosted Chef. We're going to download your API keys
and knife config from Opscode and install them on your system.

Before you continue, please be aware that this program will update your API key
and your organization's validation key. The existing keys for these accounts
will be expired and no longer valid.

Your config will be created in #{@config_installer.install_dir}

WELCOME

      unless HighLine.new.agree("Ready to get started? (yes/no): ")
        STDERR.puts "goodbye."
        exit 1
      end
    end

    def setup_and_validate
      @validator.validate!
    end

    def fetch_and_install
      @config_installer.install_all
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
      @config_installer.validate!
      greeting
      @options.ask_for_missing_opts
      setup_and_validate
      fetch_and_install
      goodbye
    rescue Interrupt, EOFError
      puts "\nexiting..."
      exit! 1
    end

  end
end




