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

        test 'If cash is already present, it updates attributes' do
          cash = create(:cash, iban: @bank_information[:iban])
          Integrations::Baqio::Handlers::Cashes.new(vendor: EkylibreBaqio::VENDOR,
bank_informations: @bank_informations).bulk_find_or_create
          updated_cash = cash.reload
          assert_equal(@bank_information[:domiciliation], cash.name )
          assert_equal(@bank_information[:domiciliation], cash.bank_name )
          assert_equal(@bank_information[:bic], cash.bank_identifier_code )
          assert_equal(@bank_information[:owner], cash.bank_account_holder_name )
          assert_equal(@bank_information[:primary], cash.by_default )
          assert(cash.provider.blank?)
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
          assert_hash_equal({ data: { 'id'=>'299960', 'primary'=>true }, name: 'Baqio_bank_information', vendor: 'baqio' }, cash.provider)
        end

        def assert_hash_equal(expected, actual)
          actual.keys.each do |key|
            if actual[key].is_a?(Hash)
              assert_hash_equal(expected[key], actual[key])
            else
              assert_equal(expected[key], actual[key])
            end
          end
        end
      end
    end
  end
end
