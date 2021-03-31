# Maintain your gem's version:
require_relative "lib/ekylibre-baqio/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name = "ekylibre-baqio"
  spec.version = EkylibreBaqio::VERSION
  spec.authors = ['Ekylibre developers']
  spec.email = ['dev@ekylibre.com']

  spec.summary = "Baqio plugin for Ekylibre"
  spec.required_ruby_version = '>= 2.6.0'
  spec.homepage = 'https://www.ekylibre.com'
  spec.license = 'AGPL-3.0-only'

  spec.files = Dir.glob(%w[{app,config,db,lib}/**/* LICENSE.md])

  spec.require_path = ['lib']

  spec.add_dependency 'dotenv', '~> 2.7'
  spec.add_dependency 'vcr', '~> 6.0'
  spec.add_dependency 'webmock', '~> 3.11'

  spec.add_development_dependency 'rubocop', '1.11.0'
end
