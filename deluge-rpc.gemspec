# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'deluge/rpc/version'

Gem::Specification.new do |spec|
  spec.name          = 'deluge-rpc'
  spec.version       = Deluge::Rpc::VERSION
  spec.authors       = ['Igor Yamolov']
  spec.email         = ['clouster@yandex.ru']
  spec.summary       = 'Deluge RPC protocol wrapper'
  spec.description   = 'Communicate with Deluge torrent client via RPC protocol'
  spec.homepage      = 'https://github.com/t3hk0d3/deluge-rpc'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.6' # rubocop:disable Gemspec/RequiredRubyVersion

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'concurrent-ruby', '~> 1.1.8'
  spec.add_dependency 'rencoder', '~> 0.2'

  spec.add_development_dependency 'rspec', '~> 3.10.0'
  spec.add_development_dependency 'rubocop', '~> 0.90'
  spec.add_development_dependency 'rubocop-rspec', '~> 1.43'
end
