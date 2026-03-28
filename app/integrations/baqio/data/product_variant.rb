# frozen_string_literal: true

module Integrations
  module Baqio
    module Data
      class ProductVariant
        def initialize(variant_id)
          @variant_id = variant_id
        end

        def result
          @formated_data ||= call_api
        end

        def format_data(product_variant)
          data_product_variant = product_variant.filter { |k, _v| main_desired_fields.include?(k) }
          data_product_variant[:product] = format_product_variants_product(product_variant[:product])

          if product_variant[:product_size].present?
            data_product_variant[:product_size] = format_product_variants_product_size(product_variant[:product_size])
          end

          if product_variant[:product_vintage].present?
            data_product_variant[:product_vintage] = format_product_variants_product_vintage(product_variant[:product_vintage])
          end

          data_product_variant
        end

        private

          def call_api
            ::Baqio::BaqioIntegration.fetch_product_variant(@variant_id).execute do |c|
              c.success do |list|
                format_data(list)
              end
            end
          end

          def main_desired_fields
            %i[id sku default_barcode]
          end

          def format_product_variants_product(product_variants_product)
            desired_fields = %i[name product_family_id product_category_id kind appellation product_color]
            data = product_variants_product.filter { |k, _v| desired_fields.include?(k) }
            data[:product_family] = format_product_variants_product_family(product_variants_product[:product_family])
            data
          end

          def format_product_variants_product_vintage(product_variants_product_vintage)
            desired_fields = %i[vintage primeur grapes wine_ageing]
            data = product_variants_product_vintage.filter { |k, _v| desired_fields.include?(k) }
            data
          end

          def format_product_variants_product_size(product_variants_product_size)
            desired_fields = %i[id name short_name kind updated_at]
            data = product_variants_product_size.filter { |k, _v| desired_fields.include?(k) }
            data
          end

          def format_product_variants_product_family(product_variants_product_family)
            desired_fields = %i[name]
            data = product_variants_product_family.filter { |k, _v| desired_fields.include?(k) }
            data
          end

      end
    end
  end
end
