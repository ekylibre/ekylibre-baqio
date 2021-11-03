require 'test_helper'
require EkylibreBaqio::Engine.root.join('test','baqio_test_helper')

class BaqioFetchUpdateCreateJobTest < Ekylibre::Testing::ApplicationTestCase::WithFixtures
  setup do
    VCR.use_cassette('auth') do
      Integration.create(nature: 'baqio', parameters: { api_key: ENV['API_KEY'], api_password: ENV['API_PASSWORD'], api_secret: ENV['API_SECRET'], url: ENV['API_URL'] })
    end
  end

  test 'import job' do
    VCR.use_cassette('full_import') do |cassette|
      assert_differences([
        ['::Cash.count', 1],
        ['::Entity.count', 1],
        ['::Sale.count', 0]
          ]) do
        BaqioFetchUpdateCreateJob.perform_now 
      end
    end
  end
end
