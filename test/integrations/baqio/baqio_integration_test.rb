require 'test_helper'
require EkylibreBaqio::Engine.root.join('test','baqio_test_helper')

class BaqioIntegrationTest < ::Ekylibre::Testing::ApplicationTestCase::WithFixtures
  setup do
    VCR.use_cassette('check') do
      Integration.create(nature: 'baqio', parameters: { api_key: ENV['API_KEY'], api_password: ENV['API_PASSWORD'], api_secret: ENV['API_SECRET'], url: ENV['API_URL'] })
    end
  end

  def test_family_product
    VCR.use_cassette('family_product') do |cassette|
      Baqio::BaqioIntegration.fetch_family_product.execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash'
          assert %i[id name handle inventory kind].all? { |s| response.first.key? s }, 'Should have correct attributes'
        end
      end
    end
  end

  def test_orders
    VCR.use_cassette('order') do
      Baqio::BaqioIntegration.fetch_orders(1).execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash'
          assert %i[id account_id customer_id fulfillment_status total_price_cents].all? { |s|response.first.key? s }, 'Should have correct attributes'
        end
      end
    end
  end

  def test_payment_sources
    VCR.use_cassette('payment_sources') do
      Baqio::BaqioIntegration.fetch_payment_sources.execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash'
          assert %i[id name bank_information_id].all? { |s| response.first.key? s }, 'Should have correct attributes'
        end
      end
    end
  end

  def test_fetch_bank_informations
    VCR.use_cassette('bank_informations') do
      Baqio::BaqioIntegration.fetch_bank_informations.execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash'
          assert %i[id iban domiciliation bic owner primary].all? { |s| response.first.key? s }, 'Should have correct attributes'
        end
      end
    end
  end

  def test_product_variants
    VCR.use_cassette('product_variants') do
      Baqio::BaqioIntegration.fetch_product_variants(40875).execute do |call|
        call.success do |response|
          assert_equal Hash, response.class, 'Should return an hash'
          assert %i[id product].all? { |s| response.key? s }, 'Should have correct attributes'
          assert %i[product_category_id product_family_id].all? { |s|response[:product].key? s }, 'Should have correct product attributes'
        end
      end
    end
  end

  def test_country_taxes
    VCR.use_cassette('country_taxes') do
      Baqio::BaqioIntegration.fetch_country_taxes.execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash'
          assert %i[id code tax_percentage tax_type].all? { |s| response.first.key? s }, 'Should have correct attributes'
        end
      end
    end
  end
end
