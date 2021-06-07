require 'rest-client'

module Baqio
  class ServiceError < StandardError; end

  class BaqioIntegration < ActionIntegration::Base
    # Set url needed for Baqio API v2
    BASE_URL = 'https://demo.baqio.com/api/v1'.freeze
    FAMILY_URL = BASE_URL + '/product_families'
    ORDERS_URL = BASE_URL + '/orders'
    VARIANTS_URL = BASE_URL + '/product_variants'
    PAYMENT_SOURCES_URL = BASE_URL + '/payment_sources'
    BANK_INFORMATIONS_URL = BASE_URL + '/bank_informations'
    COUNTRY_TAXES_URL = BASE_URL + '/country_taxes'

    authenticate_with :check do
      parameter :api_key
      parameter :api_password
      parameter :api_secret
    end

    calls :authentication_header, :fetch_payment_sources, :fetch_bank_informations, :fetch_family_product, :fetch_orders,
          :fetch_product_variants, :fetch_country_taxes

    # Build authentication header with api_key and password parameters
    # DOC https://api-doc.baqio.com/docs/api-doc/Baqio-Public-API.v1.json
    def authentication_header
      integration = fetch integration
      string_to_encode = "#{integration.parameters['api_key']}:#{integration.parameters['api_password']}"
      auth_encode = Base64.encode64(string_to_encode).delete("\n")
      headers = { authorization: "Basic #{auth_encode}", content_type: :json, accept: :json }
    end

    # https://api-doc.baqio.com/docs/api-doc/Baqio-Public-API.v1.json/paths/~1payment_sources/get
    def fetch_payment_sources
      # Call API
      get_json(PAYMENT_SOURCES_URL, authentication_header) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    # https://api-doc.baqio.com/docs/api-doc/Baqio-Public-API.v1.json/components/schemas/BankInformation
    def fetch_bank_informations
      # Call API
      get_json(BANK_INFORMATIONS_URL, authentication_header) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    # GET recupérer la liste des familles de produits - OK
    def fetch_family_product
      # Call API
      get_json(FAMILY_URL, authentication_header) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    # https://api-doc.baqio.com/docs/api-doc/Baqio-Public-API.v1.json/paths/~1orders/get
    def fetch_orders(page)
      # Call API
      get_json(ORDERS_URL + "?page=#{page}", authentication_header) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    def fetch_product_variants(product_variant_id)
      get_json(VARIANTS_URL + "/#{product_variant_id}", authentication_header) do |r|
        r.success do
          list = JSON(r.body).deep_symbolize_keys
        end
      end
    end

    def fetch_country_taxes
      # Call API
      get_json(COUNTRY_TAXES_URL, authentication_header) do |r|
        r.success do
          list = JSON(r.body).map(&:deep_symbolize_keys)
        end
      end
    end

    # TODO: fetch_incoming_payment_modes
    # https://api-doc.baqio.com/docs/api-doc/Baqio-Public-API.v1.json/paths/~1payment_sources/get

    # Check if the API is up
    def check(integration = nil)
      integration = fetch integration
      puts integration.inspect.red
      string_to_encode = "#{integration.parameters['api_key']}:#{integration.parameters['api_password']}"
      auth_encode = Base64.encode64(string_to_encode).delete("\n")
      header = { authorization: "Basic #{auth_encode}", content_type: :json, accept: :json }
      get_json(FAMILY_URL, header) do |r|
        if r.state == :success
          puts 'check success'.inspect.green
          Rails.logger.info 'CHECKED'.green
        end
        r.error :wrong_password if r.state == '401'
        r.error :no_account_exist if r.state == '404'
      end
    end

  end
end
