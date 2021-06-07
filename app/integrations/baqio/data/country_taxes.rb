# frozen_string_literal: true

module Integrations
  module Baqio
    module Data
      class CountryTaxes
        def initialize(country_tax_id:)
          @formated_data = nil
          @country_tax_id = country_tax_id
        end

        def result
          @formated_data ||= call_api
        end

        def format_data(list)
          list.map do |country_tax|
            country_tax.filter{ |k, _v| desired_fields.include?(k) }
          end
        end

        private

          def call_api
            ::Baqio::BaqioIntegration.fetch_country_taxes.execute do |c|
              c.success do |list|
                format_data(list.select{ |ct| ct[:id] == @country_tax_id } )
              end
            end
          end

          def desired_fields
            %i[code tax_percentage tax_type]
          end

      end
    end
  end
end
