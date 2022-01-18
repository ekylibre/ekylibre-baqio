# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class ProductNatureVariants

        def initialize(vendor:)
          @vendor = vendor
        end

        def bulk_find_or_create
          Integrations::Baqio::Data::ProductVariants.new.result.each do |product_variant|
            product_nature_variant = ProductNatureVariant.of_provider_vendor(@vendor).of_provider_data(:id, product_variant[:id].to_s).first
            next if product_nature_variant.present?

            create_product_variant(product_variant)
          end
        end

        private

          def create_product_variant(product_variant)
            if product_variant[:sku] == 'ZDISCOUNT'
              create_product_nature_variant_discount_and_reduction(product_variant)
            elsif product_variant[:product][:kind] == 'standard'
              create_product_nature_variant(product_variant)
              find_or_create_conditioning(product_variant[:product_size])
            elsif product_variant[:product][:kind] == 'other'
              create_product_nature_variant_additional_activity(product_variant)
            elsif product_variant[:product][:kind] == 'pack'
              create_product_nature_variant_packaging(product_variant)
            end
          end

          def create_product_nature_variant(product_variant)
            # Find Baqio product_family_id and product_category_id to find product nature and product category at Ekylibre
            baqio_product_category_id = product_variant[:product][:product_category_id]
            baqio_product_family_id = product_variant[:product][:product_family_id]

            nature_id = baqio_product_category_id.nil? ? '1' : baqio_product_category_id.to_s
            category_id = baqio_product_family_id.to_s

            product_nature_category = ProductNatureCategory.of_provider_vendor(@vendor).of_provider_data(:id, category_id).first
            product_nature = find_or_create_product_nature(@vendor, nature_id, product_nature_category)

            import_variant = ProductNatureVariant.import_from_lexicon(:wine)
            reference_unit = Unit.import_from_lexicon('liter')

            # If sku is nil add product_size to name
            name_complement = product_variant[:sku].present? ? product_variant[:sku] : product_variant[:product_size][:short_name]
            baqio_variant_name = [product_variant[:product][:name], product_variant[:vintage], product_variant[:product][:appellation],
                                  product_variant[:product][:product_color][:name], name_complement].reject(&:blank?).join(' - ')

            variant = ProductNatureVariant.new
            variant.name = baqio_variant_name
            variant.category_id = product_nature_category.id
            variant.nature_id = product_nature.id
            variant.active = import_variant.active
            variant.type = import_variant.type
            variant.default_quantity = 1
            variant.default_unit_name = reference_unit.reference_name
            variant.default_unit_id = reference_unit.id
            variant.unit_name = 'Litre'
            variant.provider = { vendor: @vendor, name: 'Baqio_product_variant',
                                data: { id: product_variant[:id].to_s } }
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

          def create_product_nature_variant_discount_and_reduction(product_variant)
            init_product_nature_variant = ProductNatureVariant.import_from_lexicon(:purchase_discount_and_reduction, true)
            product_nature_variant = ProductNatureVariant.find_or_initialize_by(name: "#{product_variant[:product][:name]} Baqio")

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
            product_nature_variant.provider =  { vendor: @vendor, name: 'Baqio_product_variant_zdiscount',
  data: { id: product_variant[:id].to_s } }
            product_nature_variant.save!

            product_nature_variant
          end

          def create_product_nature_variant_additional_activity(product_variant)
            init_product_nature_variant = ProductNatureVariant.import_from_lexicon(:additional_activity)
            product_nature_variant = ProductNatureVariant.find_or_initialize_by(name: product_variant[:product][:name])

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
            product_nature_variant.provider =  { vendor: @vendor, name: 'Baqio_product_variant_other',
  data: { id: product_variant[:id].to_s } }
            product_nature_variant.save!

            product_nature_variant
          end

          def create_product_nature_variant_packaging(product_variant)
            product_nature = ProductNature.import_from_lexicon(:packaging)
            product_nature_category = ProductNatureCategory.import_from_lexicon(:processed_product)
            reference_unit = Unit.import_from_lexicon('unity')

            product_nature_variant = ProductNatureVariant.create!(
              name: "#{product_variant[:product][:name]} - #{product_variant[:product][:product_family][:name]}",
              nature_id: product_nature.id,
              category_id: product_nature_category.id,
              variety: product_nature.variety, # TO CHECK
              active: true,
              default_quantity: 1,
              default_unit_name: reference_unit.reference_name,
              default_unit_id: reference_unit.id,
              provider:  { vendor: @vendor, name: 'Baqio_product_variant_pack',
                data: { id: product_variant[:id].to_s } }
            )

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

          def find_or_create_conditioning(product_size)
            conditioning_unit = Conditioning.of_provider_vendor(@vendor).of_provider_data(:id, product_size[:id].to_s).first

            if conditioning_unit.present?
              conditioning_unit
            else
              base_unit = Unit.import_from_lexicon('liter')

              Conditioning.create!(
                name: product_size[:name],
                base_unit: base_unit,
                coefficient: (product_size[:milliliters] &./ 1000.to_f),
                provider: { vendor: @vendor, name: 'Baqio_product_size',
data: { id: product_size[:id].to_s, updated_at: product_size[:updated_at] } },
              )
            end
          end

      end
    end
  end
end
