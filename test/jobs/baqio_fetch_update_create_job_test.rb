require 'test_helper'
require_relative '../test_helper'

class BaqioFetchUpdateCreateJobTest < Ekylibre::Testing::ApplicationTestCase::WithFixtures
  setup do
    VCR.use_cassette('auth') do
      Integration.create(nature: 'baqio',
parameters: { api_key: ENV['API_KEY'], api_password: ENV['API_PASSWORD'], api_secret: ENV['API_SECRET'] })
    end
  end

end
