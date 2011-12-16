module HostedChef

  # Talks to Hosted Chef over HTTP. Right now, uses screen scraping to fetch
  # CSRF tokens from HTML pages, but I'm optimistic that we'll at least send
  # these as JSON in the future.
  class ApiClient

    extend Forwardable

    def_delegators :@options, :username, :password, :orgname

    def initialize(options)
      @options = options
    end

    # Rails csrf token for the login page.
    def login_authenticity_token
      @auth_token ||= begin
        login_page = RestClient.get('https://manage.opscode.com')
        extract_csrf_token_from(login_page)
      end
    end

    # Rails csrf token for the user profile page on community.opscode.com
    def user_key_authenticity_token
      @user_key_authenticity_token ||= begin
        new_key_page = RestClient.get("https://community.opscode.com/users/#{username}/user_key/new", :cookies => login_cookies)
        @login_cookies = new_key_page.cookies
        extract_csrf_token_from(new_key_page)
      end
    end

    # Rails csrf token for the organization list page on manage.opscode.com
    def validator_key_authenticity_token
      @validator_key_authenticity_token ||= begin
        org_list_page = RestClient.get("https://manage.opscode.com/organizations", :cookies => login_cookies)
        @login_cookies = org_list_page.cookies
        extract_csrf_token_from(org_list_page)
      end
    end

    # Memoized cookies for authN with manage and community sites.
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

    # Fetches the knife.rb for the given user/organization pair from manage.
    def knife_config
      RestClient.get("https://manage.opscode.com/organizations/#{orgname}/_knife_config", :cookies => login_cookies)
    end

    # Fetches the user's RSA API key from community.opscode.com.
    #
    # NB: Updates state on the server such that any existing key becomes
    # invalid.
    def user_key
      post_options = {
        :authenticity_token => user_key_authenticity_token,
        :multipart => true
      }
      RestClient.post("https://community.opscode.com/users/#{username}/user_key", post_options, {:cookies => login_cookies})
    end

    # Fetches the organization's validator client's key from manage.
    #
    # NB: This updates state on the server such that any existing key for this
    # client is no longer valid.
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

    # Screen scrape the HTML in +page+ and find the csrf token. Obviously this
    # is suboptimal, but REXML can't parse HTML (AFAICT) and we don't want to
    # depend on libxml2, so really nice solutions (like nokogiri+mechanize) are
    # out. Hopefully we (opscode) will have time soon to build a saner
    # password-based auth mechanism and no one will know that I parsed HTML
    # with regexes :P
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
end
