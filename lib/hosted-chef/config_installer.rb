module HostedChef

  # Handles the business of selecting the install location and writing out the
  # API keys and knife config.
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

      if @options.folder
        [@options.folder, :non_default]
      elsif ENV['USER'] && !File.exist?(home_dot_chef)
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
end

