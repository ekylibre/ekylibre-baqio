# frozen_string_literal: true

module Integrations
  module Baqio
    module Data
      class ProductVariants
        def initialize(product_variant_id:)
          @product_variant_id = product_variant_id
        end

        def result
          @formated_data ||= call_api
        end

        def format_data(product_variants)
          data = {}
          data[:product] = format_product_variants_product(product_variants[:product])
          data
        end

        private

          def call_api
            ::Baqio::BaqioIntegration.fetch_product_variants(@product_variant_id).execute do |c|
              c.success do |list|
                format_data(list)
              end
            end
          end

          def format_product_variants_product(product_variants_product)
            desired_fields = %i[product_family_id product_category_id]
            data = product_variants_product.filter { |k, _v| desired_fields.include?(k) }
            data
          end

      end
    end
  end
end