module HostedChef

  # Controller and Presentation (yes, I know) for the Hosted Chef user setup
  # task (currently the only task).
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

      unless @options.no_input || HighLine.new.agree("Ready to get started? (yes/no): ")
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
