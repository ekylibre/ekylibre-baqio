# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class ProductNatures

        PRODUCT_CATEGORY_BAQIO = {
          1 => 'Vin tranquille', 2 => 'Vin mousseux', 3 => 'Cidre',
          4 => 'VDN et VDL AOP', 5 => 'Bière', 6 => 'Boisson fermentée autre que le vin et la bière',
          7 => 'Rhum des DOM', 8 => 'Autre produit intermédiaire que VDN et VDL AOP', 9 => 'Autre',
          10 => 'Pétillant de raisin', 11 => 'Poiré', 12 => 'Hydromel',
          13 => 'Alcool (autre que Rhum)', 14 => 'Pétillant de raisin',
          15  => 'Rhums tiers (hors DOM) et autres rhums', 16  => 'Matière première pour alcool non alimentaire',
          17  => 'Matière première pour spiritueux'
        }.freeze

        CATEGORY = :wine

        def initialize(vendor:, product_nature_id:, product_nature_category:)
          @vendor = vendor
          @product_nature_id = product_nature_id
          @product_nature_category = product_nature_category
        end

        def bulk_find_or_create
          product_nature = ProductNature.of_provider_vendor(@vendor).of_provider_data(:id, @product_nature_id.to_s).first

          if product_nature.present? && @product_nature_category.provider[:data]['kind'] == 'standart'
            product_nature
          else
            create_product_nature(@product_nature_id, @product_nature_category)
          end
        end

        private

          def create_product_nature(product_nature_id, product_nature_category)
            init_product_nature = import_product_nature_category(product_nature_category.provider[:data]['kind'])
            init_product_nature_name = init_product_nature_name(init_product_nature, product_nature_id)

            product_nature = ProductNature.find_or_initialize_by(name: init_product_nature_name)

            product_nature.variety = init_product_nature.variety
            product_nature.derivative_of = init_product_nature.derivative_of
            product_nature.reference_name = init_product_nature.reference_name
            product_nature.active = init_product_nature.active
            product_nature.evolvable = init_product_nature.evolvable
            product_nature.population_counting = init_product_nature.population_counting
            product_nature.variable_indicators_list = %i[certification reference_year temperature]
            product_nature.frozen_indicators_list = init_product_nature.frozen_indicators_list
            product_nature.type = init_product_nature.type
            product_nature.provider = { vendor: @vendor, name: 'Baqio_product_type', data: { id: product_nature_id.to_s } }
            product_nature.save!

            product_nature
          end

          def import_product_nature_category(product_nature_category_baqio_kind)
            if product_nature_category_baqio_kind == 'other'
              ProductNature.import_from_lexicon(:fee_and_external_service)
            else
              ProductNature.import_from_lexicon(CATEGORY)
            end
          end

          def init_product_nature_name(init_product_nature, product_nature_id)
            if init_product_nature.reference_name == 'fee_and_external_service'
              "#{init_product_nature.name} (Baqio)"
            else
              PRODUCT_CATEGORY_BAQIO[product_nature_id.to_i]
            end
          end

      end
    end
  end
end
