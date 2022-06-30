require 'test_helper'
require_relative '../../../test_helper'

module Integrations
  module Baqio
    module Handlers
      class CashesTest < ::Ekylibre::Testing::ApplicationTestCase::WithFixtures
        setup do
          @bank_informations = [
            {
              id: 299_960,
              owner: 'Entre-deux-Terres',
              domiciliation: 'Crédit Coop',
              iban: 'FR7630004013650002851297101',
              bic: 'AGRIFRPP833',
              primary: true
            }
          ]
          @bank_information = @bank_informations.first
        end

        test "If cash doesn't exist, it create a new cash with correct attributes" do
          Integrations::Baqio::Handlers::Cashes.new(vendor: EkylibreBaqio::VENDOR,
bank_informations: @bank_informations).bulk_find_or_create
          cash = Cash.order(created_at: :desc).first
          assert_equal(@bank_information[:domiciliation], cash.name )
          assert_equal(@bank_information[:domiciliation], cash.bank_name )
          assert_equal(@bank_information[:bic], cash.bank_identifier_code )
          assert_equal(@bank_information[:owner], cash.bank_account_holder_name )
          assert_equal(@bank_information[:primary], cash.by_default )
          assert_equal(@bank_information[:iban], cash.iban)
          assert_equal('bank_account', cash.nature)
          assert_equal('iban', cash.mode)
          assert(cash.provider.blank?)
        end
      end
    end
  end
end
