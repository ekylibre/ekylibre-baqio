# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class Cashes
        BANK_ACCOUNT_PREFIX_NUMBER = '512201'

        def initialize(vendor:, bank_informations: Integrations::Baqio::Data::BankInformations.new.result )
          @vendor = vendor
          @bank_informations = bank_informations
          @cf = create_custom_fields
        end

        def bulk_find_or_create
          bank_informations.each do |bank_information|
            next if find_existant_cash(bank_information).present?

            create_cash(bank_information)
          end
        end

        private
          attr_reader :bank_informations

          def find_existant_cash(bank_information)
            iban = bank_information[:iban].gsub(/\s+/, '')
            cash = Cash.find_by(iban: iban)
            if cash.present?
              if cash.custom_value(@cf) != bank_information[:id].to_s
                cash.set_custom_value(@cf, bank_information[:id].to_s)
                cash.save!
              end
            end
            cash
          end

          def create_cash(bank_information)
            account = find_or_create_account(bank_information)
            journal = create_journal(bank_information)

            cash = Cash.create!(
              name: bank_information[:domiciliation],
              nature: 'bank_account',
              bank_name: bank_information[:domiciliation],
              mode: 'iban',
              iban: bank_information[:iban],
              bank_identifier_code: bank_information[:bic],
              journal_id: journal.id,
              main_account_id: account.id,
              bank_account_holder_name: bank_information[:owner],
              by_default: bank_information[:primary]
            )
            cash.set_custom_value(@cf, bank_information[:id].to_s)
            cash.save
          end

          def find_or_create_account(bank_information)
            account = Account.of_provider_vendor(@vendor).of_provider_data(:id, bank_information[:id].to_s).first

            if account
              account
            else
              # Select all Baqio account at Ekylibre
              accounts = Account.select{ |a| a.number.first(4) == BANK_ACCOUNT_PREFIX_NUMBER.first(4) }

              # Select all account number with the first 6 number
              accounts_number_without_suffix =  accounts.map { |a| a.number[0..5].to_i }

              # For the first synch if there is no Baqio account at Ekylibre
              account_number_final =  if accounts_number_without_suffix.max.nil?
                                        BANK_ACCOUNT_PREFIX_NUMBER.to_i
                                      else
                                        accounts_number_without_suffix.max
                                      end
              # Take the bigger number and add 1
              account_number = (account_number_final + 1).to_s
              baqio_account_number = Accountancy::AccountNumberNormalizer.build_deprecated_for_account_creation.normalize!(account_number)

              account = Account.create!(
                number: baqio_account_number,
                name: 'Banque ' + bank_information[:domiciliation],
                provider: provider_value(id: bank_information[:id].to_s)
              )
            end
          end

          def create_journal(bank_information)
            baqio_journals = Journal.select{ |journal| journal.code.first(3) == 'BQB' }
            baqio_journals_last_code_number = baqio_journals.map { |journal| journal.code[3].to_i }

            baqio_journal_code =  if baqio_journals_last_code_number.empty?
                                    1
                                  else
                                    baqio_journals_last_code_number.max + 1
                                  end

            journal = Journal.create!(
              name: 'Banque ' + bank_information[:domiciliation],
              nature: 'bank',
              code: "BQB#{baqio_journal_code}",
              provider: provider_value(id: bank_information[:id].to_s)
            )
          end

          # providable methods
          def provider_value(**data)
            { vendor: @vendor, name: provider_name, data: data }
          end

          def provider_name
            'Baqio_bank_information'
          end

          def create_custom_fields
            k = :bank_information_id
            v = 'Identifiant bancaire Baqio'
            # create custom field if not exist
            if cf = CustomField.find_by(column_name: k.to_s, customized_type: 'Cash')
              cf
            else
              CustomField.create!(name: v, customized_type: 'Cash',
                                         nature: 'text',
                                         active: true,
                                         required: false,
                                         column_name: k.to_s)
            end
          end

      end
    end
  end
end
