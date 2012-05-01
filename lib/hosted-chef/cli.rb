module HostedChef
  class InvalidPassword < RuntimeError
  end

  class Options
    attr_writer :password

    def password
      die "No password specified" if !@password && no_input
      @password ||= HighLine.new.ask("Your Hosted Chef password: ") {|q| q.echo = "*"}
    end

    attr_writer :username

    def username
      die "No username specified" if !@username && no_input
      @username ||= HighLine.new.ask("Your Hosted Chef username? ")
    end

    attr_writer :orgname

    def orgname
      die "No orgname specified" if !@orgname && no_input
      @orgname ||= HighLine.new.ask("Your Hosted Chef organization? ")
    end

    attr_accessor :no_input

    attr_accessor :folder

    # force evaluation of options
    def ask_for_missing_opts
      username
      password
      orgname
    end

    def die(msg)
      STDERR.puts msg
      exit 1
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
      page = RestClient.get("https://www.opscode.com/account/organizations/#{orgname}/plan", :cookies => @api_client.login_cookies)
      # TODO: use actual HTTP response codes.
      puts "* Organization name '#{orgname}' is correct"
    rescue RestClient::ResourceNotFound
      STDERR.puts "The organization '#{orgname}' does not exist or you dont "\
        "have permission to access it. Check your spelling, or visit "\
        "https://manage.opscode.com/organizations to create your organization"
      exit 1
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

        o.on("-n", "--no-input", "Do not ask for confirmation") do
          options.no_input = true
        end

        o.on("-f", "--folder FOLDER", "Folder to write to") do |folder|
          options.folder = folder
        end

        o.on('-h', "--help") do
          puts o
          exit 1
        end
      end
    end

  end
end

