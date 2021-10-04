# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class ProductNatureCategories

        def initialize(vendor:)
          @vendor = vendor
        end

        def bulk_find_or_create
          Integrations::Baqio::Data::ProductFamilies.new.result.each do |family_product|
            next if find_existant_product_nature_category(family_product).present?

            create_product_nature_category(family_product)
          end
        end

        private

          def find_existant_product_nature_category(family_product)
            ProductNatureCategory.of_provider_vendor(@vendor).of_provider_data(:id, family_product[:id].to_s).first
          end

          def create_product_nature_category(family_product)
            init_category = import_product_nature_category(family_product[:kind])
            product_nature_category = ProductNatureCategory.find_or_initialize_by(name: family_product[:name])

            product_nature_category.pictogram = init_category.pictogram
            product_nature_category.active = family_product[:displayed]
            product_nature_category.depreciable = init_category.depreciable
            product_nature_category.saleable = init_category.saleable
            product_nature_category.purchasable = init_category.purchasable
            product_nature_category.storable = init_category.storable
            product_nature_category.reductible = init_category.reductible
            product_nature_category.subscribing = init_category.subscribing
            product_nature_category.product_account_id = init_category.product_account_id
            product_nature_category.stock_account_id = init_category.stock_account_id
            product_nature_category.fixed_asset_depreciation_percentage = init_category.fixed_asset_depreciation_percentage
            product_nature_category.fixed_asset_depreciation_method = init_category.fixed_asset_depreciation_method
            product_nature_category.stock_movement_account_id = init_category.stock_movement_account_id
            product_nature_category.type = init_category.type
            product_nature_category.provider = {
                                              vendor: @vendor,
                                              name: 'Baqio_product_family',
                                              data: { id: family_product[:id].to_s, kind: family_product[:kind].to_s }
                                              }

            product_nature_category.save!
          end

          def import_product_nature_category(family_product_kind)
            if family_product_kind == 'other'
              ProductNatureCategory.import_from_lexicon(:additional_activity)
            else
              ProductNatureCategory.import_from_lexicon(:processed_product)
            end
          end
      end
    end
  end
end
