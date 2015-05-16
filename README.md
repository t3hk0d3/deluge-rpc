# Deluge::Api

Ruby RPC client library for Deluge torrent client.  
Provides dynamic API bindings depending on RPC server.  
Multi-threading friendly, thanks to ``concurrent-ruby`` gem.

Official RPC protocol documentation:  
http://deluge.readthedocs.org/en/develop/core/rpc.html

Deluge RPC API reference:  
http://deluge.readthedocs.org/en/develop/core/rpc.html#remote-api

## Usage

```ruby
require 'deluge'

# Initialize client
client = Deluge::Api::Client.new(host: 'localhost', port: 58846, login: 'username', password: 'password')

# Start connection and authenticate
client.start

# Get auth level
client.auth_level
# => 5

# Get available methods
client.api_methods
# => ['daemon.add_torrent_file', 'core.shutdown', ...]

# Get deluge version
client.daemon.info
# => "1.3.10"

# Get torrents list
client.core.get_torrents_status({}, ['name', 'hash'])
# => [{name: 'Hot Chicks Action', hash: '<torrent_hash>'}, ...]

# Get namespace
core = client.core
# => <Deluge::Api::Namespace name="core">

# Get namespace methods
core.api_methods
# => ['core.get_session_status', 'core.get_upload_rate', ....]

# Invoke namespace method
core.get_config
# => {"info_sent"=>0.0, "lsd"=>true, "send_info"=>false, ... }

# Close connection
client.close
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'deluge-api'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install deluge-api
