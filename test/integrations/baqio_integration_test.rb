require 'test_helper'
require_relative '../test_helper'

class BaqioIntegrationTest < ::Ekylibre::Testing::ApplicationTestCase::WithFixtures
  setup do
    VCR.use_cassette("auth") do
      Integration.create(nature: 'baqio', parameters: { api_key: ENV['API_KEY'], api_password: ENV['API_PASSWORD'], api_secret: ENV['API_SECRET'] })
    end
  end

  def test_family_product
    VCR.use_cassette("family_product") do
      Baqio::BaqioIntegration.fetch_family_product.execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash counter'
          assert %i[id name handle inventory kind].all? { |s| response.first.key? s }, 'Should have correct attributes'
        end
      end
    end
  end

  def test_orders
    VCR.use_cassette("order") do
      Baqio::BaqioIntegration.fetch_orders.execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash counter'
          assert %i[id account_id customer_id fulfillment_status total_price_cents].all? { |s| response.first.key? s }, 'Should have correct attributes'
        end
      end
    end
  end
end
