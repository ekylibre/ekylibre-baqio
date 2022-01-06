# frozen_string_literal: true

module Integrations
  module Baqio
    module Data
      class ProductVariants
        def result
          @formated_data ||= call_api
        end

        def format_data(list)
          list.map do |product_variant|
            data_product_variant = product_variant.filter { |k, _v| main_desired_fields.include?(k) }
            data_product_variant[:product] = format_product_variants_product(product_variant[:product])

            if product_variant[:product_size].present?
              data_product_variant[:product_size] = format_product_variants_product_size(product_variant[:product_size])
            end

            data_product_variant
          end
        end

        private

          def call_api
            ::Baqio::BaqioIntegration.fetch_product_variants.execute do |c|
              c.success do |list|
                format_data(list)
              end
            end
          end

          def main_desired_fields
            %i[id vintage sku]
          end

          def format_product_variants_product(product_variants_product)
            desired_fields = %i[name product_family_id product_category_id kind appellation product_color]
            data = product_variants_product.filter { |k, _v| desired_fields.include?(k) }
            data
          end

          def format_product_variants_product_size(product_variants_product_size)
            desired_fields = %i[id name milliliters short_name kind updated_at]
            data = product_variants_product_size.filter { |k, _v| desired_fields.include?(k) }
            data
          end

      end
    end
  end
end
