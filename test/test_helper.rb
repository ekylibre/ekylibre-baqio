require 'vcr'
require('dotenv')

# TODO: Files under app/integration/** are not load in test.
# Reorganise folder structure and module
Dir.glob(EkylibreBaqio::Engine.root.join('app', 'integrations', '**', '*.rb')).sort.each do |file|
  require file
end

Dotenv.load(File.join(EkylibreBaqio::Engine.root, '.env'))

VCR.configure do |config|
  config.allow_http_connections_when_no_cassette = false
  config.cassette_library_dir = File.expand_path('cassettes', __dir__)
  config.hook_into :webmock
  config.ignore_request { ENV['DISABLE_VCR'] }
  config.ignore_localhost = true
end
