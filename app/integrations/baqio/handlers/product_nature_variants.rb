# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class ProductNatureVariants

        PRODUCT_CATEGORY_BAQIO = {
          1 => 'Vin tranquille', 2 => 'Vin mousseux', 3 => 'Cidre',
          4 => 'VDN et VDL AOP', 5 => 'Bière', 6 => 'Boisson fermentée autre que le vin et la bière',
          7 => 'Rhum des DOM', 8 => 'Autre produit intermédiaire que VDN et VDL AOP', 9 => 'Autre',
          10 => 'Pétillant de raisin', 11 => 'Poiré', 12 => 'Hydromel',
          13 => 'Alcool (autre que Rhum)', 14 => 'Pétillant de raisin',
          15  => 'Rhums tiers (hors DOM) et autres rhums', 16  => 'Matière première pour alcool non alimentaire',
          17  => 'Matière première pour spiritueux'
        }.freeze

        CATEGORY = 'wine'

        def initialize(vendor:, order_line_not_deleted:)
          @vendor = vendor
          @order_line_not_deleted = order_line_not_deleted
          @init_product_nature = ProductNature.find_by(reference_name: CATEGORY) || ProductNature.import_from_nomenclature(CATEGORY)
        end

        def bulk_find_or_create
          find_or_create_variant(@order_line_not_deleted)
        end

        private

          def find_or_create_variant(order_line_not_deleted)
            product_nature_variant = ProductNatureVariant.of_provider_vendor(@vendor).of_provider_data(:id,
                                                                                                       order_line_not_deleted[:product_variant_id].to_s).first

            if product_nature_variant.present?
              product_nature_variant
            elsif order_line_not_deleted[:description] == 'ZDISCOUNT'
              create_product_nature_variant_discount_and_reduction(order_line_not_deleted)
            else
              # Find Baqio product_family_id and product_category_id to find product nature and product category at Ekylibre
              product_variants = fetch_baqio_product_variants(order_line_not_deleted[:product_variant_id])
              product_nature_id = product_variants[:product_category_id].to_s
              product_category_id = product_variants[:product_family_id].to_s

              product_nature = find_or_create_product_nature(product_nature_id)
              product_nature_category = ProductNatureCategory.of_provider_vendor(@vendor).of_provider_data(:id, product_category_id).first

              # Find or create new variant
              product_nature_variant =  ProductNatureVariant.create!(
                category_id: product_nature_category.id,
                nature_id: product_nature.id,
                name: "#{order_line_not_deleted[:name]} - #{order_line_not_deleted[:complement]} - #{order_line_not_deleted[:description]}",
                unit_name: 'Unité',
                provider: { vendor: @vendor, name: 'Baqio_order_line_not_deleted',
data: { id: order_line_not_deleted[:product_variant_id].to_s } }
              )
            end
          end

          def fetch_baqio_product_variants(product_variant_id)
            Integrations::Baqio::Data::ProductVariants.new(product_variant_id: product_variant_id).result
          end

          def find_or_create_product_nature(product_nature_id)
            product_nature = ProductNature.of_provider_vendor(@vendor).of_provider_data(:id, product_nature_id.to_s).first

            if product_nature.present?
              product_nature
            else
              product_nature = ProductNature.find_or_initialize_by(name: PRODUCT_CATEGORY_BAQIO[product_nature_id.to_i])

              product_nature.variety = @init_product_nature.variety
              product_nature.derivative_of = @init_product_nature.derivative_of
              product_nature.reference_name = @init_product_nature.reference_name
              product_nature.active = @init_product_nature.active
              product_nature.evolvable = @init_product_nature.evolvable
              product_nature.population_counting = @init_product_nature.population_counting
              product_nature.variable_indicators_list = %i[certification reference_year temperature]
              product_nature.frozen_indicators_list = @init_product_nature.frozen_indicators_list
              product_nature.type = @init_product_nature.type
              product_nature.provider = { vendor: @vendor, name: 'Baqio_product_type', data: { id: product_nature_id.to_s } }
              product_nature.save!

              product_nature
            end
          end

          def create_product_nature_variant_discount_and_reduction(order_line_not_deleted)
            init_product_nature_variant = ProductNatureVariant.import_from_nomenclature(:discount_and_reduction, true)
            product_nature_variant = ProductNatureVariant.find_or_initialize_by(name: "#{order_line_not_deleted[:name]}Baqio")

            product_nature_variant.category_id = init_product_nature_variant.category_id
            product_nature_variant.nature_id = init_product_nature_variant.nature_id
            product_nature_variant.work_number = init_product_nature_variant.work_number
            product_nature_variant.variety = init_product_nature_variant.variety
            product_nature_variant.unit_name = init_product_nature_variant.unit_name
            product_nature_variant.active = init_product_nature_variant.active
            product_nature_variant.type = init_product_nature_variant.type
            product_nature_variant.provider =  { vendor: @vendor, name: 'Baqio_order_line_not_deleted_zdiscount',
  data: { id: order_line_not_deleted[:product_variant_id].to_s } }
            product_nature_variant.save!

            product_nature_variant
          end

      end
    end
  end
end
