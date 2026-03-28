# frozen_string_literal: true

module Integrations
  module Baqio
    module Data
      class ProductFamilies

        BAQIO_FAMILIES_HANDLE_TO_LEXICON_CATEGORIES = {
          'standard' => 'processed_product', # vin et spiritueux
          'matieres-seches' => 'packaging_wine_dry_material',
          'produit-de-transformation'  => 'processed_product',
          'remise'  => 'purchase_discount_and_reduction',
          'transport'  => 'transportation',
          'visites-exploitation ' => 'additional_activity',
          'coffrets'  => 'additional_activity',
          'divers'  => 'additional_activity'
        }.freeze

        def result
          @formated_data ||= call_api
        end

        def format_data(list)
          list.map do |family_product|
            family_product.filter{ |k, _v| desired_fields.include?(k) }
            family_product[:lexicon_category] = BAQIO_FAMILIES_HANDLE_TO_LEXICON_CATEGORIES[family_product[:handle]]
            family_product
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
            %i[id name handle displayed inventory kind]
          end

      end
    end
  end
end
