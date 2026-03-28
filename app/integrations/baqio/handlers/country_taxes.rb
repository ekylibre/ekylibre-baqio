# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class CountryTaxes

        BAQIO_TAX_TYPE_TO_EKY = {
          standard: 'normal_vat',
          intermediate: 'intermediate_vat',
          reduced: 'reduced_vat',
          exceptional: 'particular_vat',
          guadeloupe_martinique_reunion: 'particular_vat'
        }.freeze

        EU_CT_CODE = %w[AT BE DE DK FI LU IT NL ES PT].freeze

        def initialize(vendor:)
          @vendor = vendor
        end

        def bulk_find_or_create
          Integrations::Baqio::Data::CountryTaxes.new.result.each do |baqio_tax|
            next if (baqio_tax[:tax_name] != 'TVA' || baqio_tax[:primary] == false)

            find_or_create_tax(baqio_tax)
          end
          Tax.clean_inactive!
        end

        def find_or_create_specific_tax(country_tax_id)
          baqio_tax = Integrations::Baqio::Data::CountryTaxes.new(country_tax_id: country_tax_id).result.first
          # case EU
          if EU_CT_CODE.include?(baqio_tax[:code].upcase)
            existing_baqio_tax = Tax.find_by(country: baqio_tax[:code].downcase, amount: baqio_tax[:tax_percentage].to_f, nature: 'export_private_eu_vat')
            existing_baqio_tax ||= create_specific_tax('export_private_eu_vat', baqio_tax)
            existing_baqio_tax
          end
        end

        private

          def find_or_create_tax(baqio_tax)
            puts "baqio_tax #{baqio_tax}".inspect.yellow
            tax = Tax.of_provider_vendor(@vendor).of_provider_data(:id, baqio_tax[:id].to_s).first
            unless tax
              country_tax_code = baqio_tax[:code].downcase
              country_tax_percentage = baqio_tax[:tax_percentage].to_f
              if baqio_tax[:tax_type].present?
                country_tax_type = BAQIO_TAX_TYPE_TO_EKY[baqio_tax[:tax_type].to_sym]
              else
                country_tax_type = 'normal_vat'
              end

              if country_tax_code.present? && country_tax_type.present?
                item = Onoma::Tax.find_by(country: country_tax_code.to_sym, amount: country_tax_percentage, nature: country_tax_type.to_sym)
              end

              existing_baqio_tax = Tax.find_by(country: country_tax_code, amount: country_tax_percentage, nature: country_tax_type)

              # tax already present in Ekylibre, update with baqio provider
              if existing_baqio_tax.present?
                existing_baqio_tax.provider = { vendor: @vendor, name: 'Baqio_tax', data: { id: baqio_tax[:id].to_s, updated_at: baqio_tax[:updated_at] } }
                existing_baqio_tax.save!
              elsif item.present?
                # Import tax from onoma with country_tax_code (:fr)
                tax = Tax.import_from_nomenclature(item.name)
                tax.provider = { vendor: @vendor, name: 'Baqio_tax', data: { id: baqio_tax[:id].to_s, updated_at: baqio_tax[:updated_at] } }
                tax.save!
              elsif country_tax_code == 'fr'
                # case FR
                # Create tax from onoma with country_tax_code (:fr) unexisting in Onoma
                create_specific_tax(country_tax_type, baqio_tax)
              end
            end
          end

          def create_specific_tax(nature, baqio_tax)
            # item in Onoma does not have the good nature, we want a specific comportment with accounting
            tax_nature = Onoma::TaxNature.find(nature)
            if tax_nature.computation_method != :percentage
              raise StandardError.new('Can import only percentage computed taxes')
            end

            attributes = {
              amount: baqio_tax[:tax_percentage].to_f,
              name: "#{baqio_tax[:tax_name]} #{baqio_tax[:code].to_s} #{baqio_tax[:tax_percentage].to_s} %",
              nature: tax_nature,
              country: baqio_tax[:code].downcase,
              active: true,
              provider: { vendor: @vendor, name: 'Baqio_tax', data: { id: baqio_tax[:id].to_s, updated_at: baqio_tax[:updated_at] } }
            }

            %i[deduction collect fixed_asset_deduction fixed_asset_collect].each do |account|
              next unless name = tax_nature.send("#{account}_account")

              tax_radical = Account.find_or_import_from_nomenclature(name)
              # check account_number_digits to build correct account number
              account_number_digits = Preference[:account_number_digits] - 2
              tax_account = Account.find_or_create_by_number("#{tax_radical.number[0..account_number_digits]}#{tax_nature.suffix}")
              tax_account.name ||= "TVA #{nature} #{tax_nature.suffix}"
              tax_account.usages ||= tax_radical.usages
              tax_account.save!

              attributes["#{account}_account_id"] = tax_account.id
            end
            Tax.create!(attributes)
          end

      end
    end
  end
end
