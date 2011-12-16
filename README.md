# Hosted Chef: The Gem #

`hosted-chef` downloads your API keys and configuration files from the
[Opscode Management Console](https://manage.opscode.com) and installs
them in the right spot on your system.

## Usage ##
This script currently resets both your user API key and your
Organization's validation key, so it's only recommended for new users
with freshly created organizations. If that's you, run:

    gem install hosted chef
    hosted-chef -u USERNAME -o ORGANIZATION
    # enter your password at the prompt.

## Who Should Use This? ##
This utility is designed to reduce friction for users new to Opscode's
Hosted Chef. If you're a Chef pro, or joining an existing Hosted Chef
organization, or running your own Chef server, there's likely little
value for you in this utility.

