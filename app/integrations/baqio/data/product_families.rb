# frozen_string_literal: true

module Integrations
  module Baqio
    module Data
      class ProductFamilies
        def result
          @formated_data ||= call_api
        end

        def format_data(list)
          list.select{ |c| c[:name] != 'Transport' }.map do |family_product|
            family_product.filter{ |k, _v| desired_fields.include?(k) }
          end
        end

        private

          def call_api
            ::Baqio::BaqioIntegration.fetch_family_product.execute do |c|
              c.success do |list|
                format_data(list)
              end
            end
          end

          def desired_fields
            %i[id name displayed]
          end

      end
    end
  end
end
