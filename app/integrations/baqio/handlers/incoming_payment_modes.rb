# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class IncomingPaymentModes
        BAQIO_CASH_NUMBER = '531201'

        def initialize(vendor:)
          @vendor = vendor
        end

        def bulk_find_or_create
          Integrations::Baqio::Data::PaymentSources.new.result.each do |payment_source|
            existing_payment = find_existant_incoming_payment_mode(payment_source)
            if existing_payment.present?
              existing_payment
            else
              create_incoming_payment_mode(payment_source)
            end
          end
        end

        private

          def find_existant_incoming_payment_mode(payment_source)
            incoming_payment_mode = IncomingPaymentMode.find_by(name: payment_source[:name])

            if incoming_payment_mode.present? && incoming_payment_mode.provider.blank?
              incoming_payment_mode.update!(provider: { vendor: @vendor, name: 'Baqio_payment_source',
                data: { id: payment_source[:id].to_s, bank_information_id: payment_source[:bank_information_id].to_s } })

              incoming_payment_mode
            else
              IncomingPaymentMode.of_provider_vendor(@vendor).of_provider_data(:id, payment_source[:id].to_s).first
            end
          end

          def create_incoming_payment_mode(payment_source)
            # IF payment source == "Espèce" we need to use Cash "Caisse" or "Create it"
            cash =  if payment_source[:name] == 'Espèces'
                      find_or_create_cash_box
                    else
                      find_cash(payment_source)
                    end

            # TODO: manage deposit with cash later
            if cash.present?
              incoming_payment_mode = IncomingPaymentMode.create!(
                name: payment_source[:name],
                cash_id: cash.id,
                active: true,
                with_accounting: true,
                with_deposit: false,
                provider: provider_value(id: payment_source[:id].to_s, bank_information_id: payment_source[:bank_information_id])
              )
            end
          end

          def find_or_create_cash_box
            account_number = Accountancy::AccountNumberNormalizer.build_deprecated_for_account_creation.normalize!(BAQIO_CASH_NUMBER.to_i)
            cashes = Cash.cash_boxes.joins(:main_account).where(accounts: { number: account_number })
            if cashes.any?
              cashes.first
            else
              account = Account.create!(
                number: account_number,
                name: 'Caisse Baqio'
              )

              journal = Journal.create!(
                name: 'Caisse Baqio',
                nature: 'cash',
                code: 'BQC1'
              )

              cash = Cash.create!(
                name: 'Caisse Baqio',
                nature: 'cash_box',
                journal_id: journal.id,
                main_account_id: account.id
              )
            end
          end

          def find_cash(payment_source)
            if payment_source[:bank_information_id].nil?
              Cash.first
            else
              Cash.of_custom_data(:bank_information_id, payment_source[:bank_information_id].to_s).first
            end
          end

          # providable methods
          def provider_value(**data)
            { vendor: @vendor, name: provider_name, data: data }
          end

          def provider_name
            'Baqio_payment_source'
          end

      end
    end
  end
end
