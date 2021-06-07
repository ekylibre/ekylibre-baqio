require 'test_helper'
require_relative '../test_helper'

class BaqioIntegrationTest < ::Ekylibre::Testing::ApplicationTestCase::WithFixtures
  setup do
    VCR.use_cassette('auth') do
      Integration.create(nature: 'baqio',
parameters: { api_key: ENV['API_KEY'], api_password: ENV['API_PASSWORD'], api_secret: ENV['API_SECRET'] })
    end
  end

  def test_family_product
    VCR.use_cassette('family_product') do
      Baqio::BaqioIntegration.fetch_family_product.execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash counter'
          assert %i[id name handle inventory kind].all? { |s| response.first.key? s }, 'Should have correct attributes'
        end
      end
    end
  end

  def test_orders
    VCR.use_cassette('order') do
      Baqio::BaqioIntegration.fetch_orders(1).execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash counter'
          assert %i[id account_id customer_id fulfillment_status total_price_cents].all? { |s|
 response.first.key? s }, 'Should have correct attributes'
          @product_variant_id = response.first[:order_lines_not_deleted].first[:product_variant_id]
        end
      end
    end
  end

  def test_payment_sources
    VCR.use_cassette('payment_sources') do
      Baqio::BaqioIntegration.fetch_payment_sources.execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash counter'
          assert %i[id name bank_information_id].all? { |s| response.first.key? s }, 'Should have correct attributes'
        end
      end
    end
  end

  def test_fetch_bank_informations
    VCR.use_cassette('bank_informations') do
      Baqio::BaqioIntegration.fetch_bank_informations.execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash counter'
          assert %i[id iban domiciliation bic owner primary].all? { |s| response.first.key? s }, 'Should have correct attributes'
        end
      end
    end
  end

  def test_product_variants
    VCR.use_cassette('product_variants') do
      Baqio::BaqioIntegration.fetch_product_variants(@product_variant_id).execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash counter'
          assert %w[id product].all? { |s| response.first.key? s }, 'Should have correct attributes'
          assert %w[product_category_id product_family_id].all? { |s|
 response.first['product'].key? s }, 'Should have correct product attributes'
        end
      end
    end
  end

  def test_country_taxes
    VCR.use_cassette('country_taxes') do
      Baqio::BaqioIntegration.fetch_country_taxes.execute do |call|
        call.success do |response|
          assert_equal Hash, response.first.class, 'Should return an array of hash counter'
          assert %i[id code tax_percentage tax_type].all? { |s| response.first.key? s }, 'Should have correct attributes'
        end
      end
    end
  end
end
