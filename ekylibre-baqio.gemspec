$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "ekylibre-baqio/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "ekylibre-baqio"
  s.version     = EkylibreBaqio::VERSION
  s.authors     = ["RG24"]
  s.email       = ["groche@ekylibre.com"]
  s.summary     = "Baqio plugin for Ekylibre"
  s.description = "Baqio plugin for Ekylibre"
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc", "Capfile"]
  s.require_path = ['lib']
  s.test_files = Dir["test/**/*"]
  s.add_dependency 'vcr'
  s.add_dependency 'webmock'
  s.add_dependency 'dotenv'
end
