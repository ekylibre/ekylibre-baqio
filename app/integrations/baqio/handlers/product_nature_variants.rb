# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class ProductNatureVariants

        def initialize(vendor:, order_line_not_deleted:)
          @vendor = vendor
          @order_line_not_deleted = order_line_not_deleted
        end

        def bulk_find_or_create
          find_or_create_variant(@order_line_not_deleted)
        end

        private

          def find_or_create_variant(order_line_not_deleted)
            product_variants = fetch_baqio_product_variants(order_line_not_deleted[:product_variant_id])
            product_id = product_variants[:product][:id]
            product_nature_variant = ProductNatureVariant.of_provider_vendor(@vendor).of_provider_data(:id, product_id.to_s).first

            if product_nature_variant.present?
              product_nature_variant
            elsif order_line_not_deleted[:description] == 'ZDISCOUNT'
              create_product_nature_variant_discount_and_reduction(order_line_not_deleted)
            elsif product_variants[:product][:kind] == 'standard'
              # Create good variant #other #pack or #standard
              create_product_nature_variant(order_line_not_deleted, product_variants)
            elsif product_variants[:product][:kind] == 'other'
              create_product_nature_variant_additional_activity(order_line_not_deleted)
            elsif product_variants[:product][:kind] == 'pack'
              # TODO : create associate variant 'pack'
            end
          end

          def fetch_baqio_product_variants(product_variant_id)
            Integrations::Baqio::Data::ProductVariants.new(product_variant_id: product_variant_id).result
          end

          def create_product_nature_variant(order_line_not_deleted, product_variants)
            # Find Baqio product_family_id and product_category_id to find product nature and product category at Ekylibre
            baqio_product_category_id = product_variants[:product][:product_category_id]
            baqio_product_family_id = product_variants[:product][:product_family_id]

            nature_id = baqio_product_category_id.nil? ? '1' : baqio_product_category_id.to_s
            category_id = baqio_product_family_id.to_s

            product_nature_category = ProductNatureCategory.of_provider_vendor(@vendor).of_provider_data(:id, category_id).first
            product_nature = find_or_create_product_nature(@vendor, nature_id, product_nature_category)

            import_variant = ProductNatureVariant.import_from_lexicon(:wine)
            reference_unit = Unit.import_from_lexicon('liter')

            variant = ProductNatureVariant.find_or_initialize_by(name: order_line_not_deleted[:name])
            variant.category_id = product_nature_category.id
            variant.nature_id = product_nature.id
            variant.active = import_variant.active
            variant.type = import_variant.type
            variant.default_quantity = 1
            variant.default_unit_name = reference_unit.reference_name
            variant.default_unit_id = reference_unit.id
            variant.provider = { vendor: @vendor, name: 'Baqio_order_line_not_deleted',
                                data: { id: product_variants[:product][:id].to_s } }
            variant.readings.build(
              indicator_name: 'net_volume',
              indicator_datatype: 'measure',
              absolute_measure_value_value: 1,
              absolute_measure_value_unit: 'liter',
              measure_value_value: 1,
              measure_value_unit: 'liter'
            )
            variant.save!

            variant
          end

          def create_product_nature_variant_discount_and_reduction(order_line_not_deleted)
            init_product_nature_variant = ProductNatureVariant.import_from_lexicon(:purchase_discount_and_reduction, true)
            product_nature_variant = ProductNatureVariant.find_or_initialize_by(name: "#{order_line_not_deleted[:name]}Baqio")

            product_nature_variant.category_id = init_product_nature_variant.category_id
            product_nature_variant.nature_id = init_product_nature_variant.nature_id
            product_nature_variant.work_number = init_product_nature_variant.work_number
            product_nature_variant.variety = init_product_nature_variant.variety
            product_nature_variant.unit_name = init_product_nature_variant.unit_name
            product_nature_variant.active = init_product_nature_variant.active
            product_nature_variant.type = init_product_nature_variant.type
            product_nature_variant.default_quantity = init_product_nature_variant.default_quantity
            product_nature_variant.default_unit_name = init_product_nature_variant.default_unit_name
            product_nature_variant.default_unit_id = init_product_nature_variant.default_unit_id
            product_nature_variant.provider =  { vendor: @vendor, name: 'Baqio_order_line_not_deleted_zdiscount',
  data: { id: order_line_not_deleted[:product_variant_id].to_s } }
            product_nature_variant.save!

            product_nature_variant
          end

          def create_product_nature_variant_additional_activity(order_line_not_deleted)
            init_product_nature_variant = ProductNatureVariant.import_from_lexicon(:additional_activity)
            product_nature_variant = ProductNatureVariant.find_or_initialize_by(name: order_line_not_deleted[:name])

            product_nature_variant.category_id = init_product_nature_variant.category_id
            product_nature_variant.nature_id = init_product_nature_variant.nature_id
            product_nature_variant.work_number = init_product_nature_variant.work_number
            product_nature_variant.variety = init_product_nature_variant.variety
            product_nature_variant.unit_name = init_product_nature_variant.unit_name
            product_nature_variant.active = init_product_nature_variant.active
            product_nature_variant.type = init_product_nature_variant.type
            product_nature_variant.default_quantity = init_product_nature_variant.default_quantity
            product_nature_variant.default_unit_name = init_product_nature_variant.default_unit_name
            product_nature_variant.default_unit_id = init_product_nature_variant.default_unit_id
            product_nature_variant.provider =  { vendor: @vendor, name: 'Baqio_order_line_not_deleted_zdiscount',
  data: { id: order_line_not_deleted[:product_variant_id].to_s } }
            product_nature_variant.save!

            product_nature_variant
          end

          def find_or_create_product_nature(vendor, product_nature_id, product_nature_category)
            product_nature = Integrations::Baqio::Handlers::ProductNatures.new(
              vendor: vendor,
              product_nature_id: product_nature_id,
              product_nature_category: product_nature_category
            )
            product_nature.bulk_find_or_create
          end

      end
    end
  end
end
