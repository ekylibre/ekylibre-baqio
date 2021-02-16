class BaqioFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  def perform
    # Page need to be set-up to fetch orders from different Baqio pages
    @page = 0

    # Set page_with_ordres to ended the job if orders page is blank
    @page_with_orders = []

    begin

      # Create ProductNatureCategory and ProductNature from Baqio product_families
      Baqio::BaqioIntegration.fetch_family_product.execute do |c|
        c.success do |list|
          list.map do |family_product|
            pnc = ProductNatureCategory.find_by(reference_name: "wine") || ProductNatureCategory.import_from_nomenclature("wine")

            pncs = ProductNatureCategory.where("provider ->> 'id' = ?", family_product[:id].to_s)
            if pncs.any?
              pncs.first
            else
              new_pnc = ProductNatureCategory.create!(
                name: family_product[:name],
                pictogram: pnc.pictogram,
                active: pnc.active,
                depreciable: pnc.depreciable,
                saleable: pnc.saleable,
                purchasable: pnc.purchasable,
                storable: pnc.storable,
                reductible: pnc.reductible,
                subscribing: pnc.subscribing,
                product_account_id: pnc.product_account_id,
                stock_account_id: pnc.stock_account_id,
                fixed_asset_depreciation_percentage: pnc.fixed_asset_depreciation_percentage,
                fixed_asset_depreciation_method: pnc.fixed_asset_depreciation_method, 
                stock_movement_account_id: pnc.stock_movement_account_id,
                type: pnc.type,
                provider: {vendor: "Baqio", name: "Baqio_product_family", id: family_product[:id]}
              )
            end

            pn = ProductNature.find_by(reference_name: "wine") || ProductNature.import_from_nomenclature("wine")

            pns = ProductNature.where("provider ->> 'id' = ?", family_product[:id].to_s)
            if pns.any?
              pns.first
            else
              new_pn = ProductNature.create!(
                name: family_product[:name],
                variety: pn.variety,
                derivative_of: pn.derivative_of,
                reference_name: pn.reference_name,
                active: pn.active,
                evolvable: pn.evolvable,
                population_counting: pn.population_counting,
                variable_indicators_list: [:certification, :reference_year, :temperature],
                frozen_indicators_list: pn.frozen_indicators_list,
                type: pn.type,
                provider: {vendor: "Baqio", name: "Baqio_product_family", id: family_product[:id]}
              )
            end
          end
        end
      end

      # Create sales from baqio order's @page +=1)
      Baqio::BaqioIntegration.fetch_orders(1).execute do |c|
        c.success do |list|
          @page_with_orders = list
          puts list.inspect.green
          list.map do |order|
            # Create or Find existing Entity / customer at Samsys
            # order[:customer][:id]
            # order[:customer][:name]
            # order[:customer][:email]
            entities = Entity.where("provider ->> 'id' = ?", order[:customer][:id].to_s)
            if entities.any?
              entity = entities.first
            else
              custom_name = if order[:customer][:billing_information][:last_name].nil? 
                              order[:customer][:billing_information][:company_name] 
                            else
                              order[:customer][:billing_information][:last_name]
                            end
              # TODO check and add custom nature (ex: Customer "Particulier" at Baqio become "Contact" nature at Ekylibre)
              # Need API update from Baqio, method customer/id doesn't work
              entity = Entity.create!(
                first_name: order[:customer][:billing_information][:first_name],
                last_name: custom_name,
                provider: {vendor: "Baqio", name: "Baqio_order_customer", id: order[:customer][:id]}
              )

              zip_city = build_address_cz(
                order[:customer][:billing_information][:city],
                order[:customer][:billing_information][:zip]
              )

              entity_addresses = Array.new([
                { mobile: order[:customer][:billing_information][:mobile] },
                { zip_city: zip_city , mail: order[:customer][:billing_information][:address1]},
                { email: order[:customer][:billing_information][:email] },
                { website: order[:customer][:billing_information][:website] }
              ])

              # Create EntityAddress for every valid entity_addresses got from Baqio
              entity_addresses.each do |entity_address|
                unless entity_address.values.first.blank?
                  if entity_address.keys.last == :mail 
                    EntityAddress.create!(
                      entity_id: entity.id,
                      canal: "mail",
                      mail_line_4: entity_address[:mail],
                      mail_line_6: entity_address[:zip_city]
                    )
                  else
                    EntityAddress.create!(
                      entity_id: entity.id,
                      canal: entity_address.keys.first.to_s,
                      coordinate: entity_address.values.first
                    )
                  end
                end
              end
            end

            # Create or Find Sale
            # order[:amount] = amount
            # order[:fulfillment_status] = status
            # order[:id] = provider id
            # order[:order_lines_not_deleted] = items
            sales = Sale.where("provider ->> 'id' = ?", order[:id].to_s)
            if sales.any?
              sale = sales.first
            else
              if order[:id] == 133607
                # Create Variants from Baqio order_lines

                order[:order_lines_not_deleted].each do |product_order|

                  product_nature_variants = ProductNatureVariant.where("provider ->> 'id' = ?", product_order[:id].to_s)
                  binding.pry

                  if product_nature_variants.any?
                    binding.pry
                    product_nature_variant = product_nature_variants.first
                  else
                    # Find Baqio product_family_id
                    Baqio::BaqioIntegration.fetch_product_variants(product_order[:product_variant_id]).execute do |c|
                      c.success do |order|
                        @product_nature_and_category_id = order["product"]["product_family_id"].to_s
                      end
                    end

                    product_nature = ProductNature.find_by("provider ->> 'id' = ?", @product_nature_and_category_id)
                    product_nature_category = ProductNatureCategory.find_by("provider ->> 'id' = ?", @product_nature_and_category_id)

                    binding.pry
                    # Find or create new variant
                    product_nature_variant =  ProductNatureVariant.create!(
                      category_id: product_nature_category.id,
                      nature_id: product_nature.id,
                      name: "#{product_order[:name]} - #{product_order[:complement]} - #{product_order[:description]}",
                      unit_name: "Unité",
                      provider: {vendor: "Baqio", name: "Baqio_product_order", id: product_order[:id]}
                    )
                  end


                end


                binding.pry
                # sale = Sale.create!(
                #   client_id: entity.id,
                #   provider: {vendor: "Baqio", name: "Baqio_order", id: order[:id]}
                # )
              end
            end

          end

        end
      end
    
    rescue StandardError => error
      Rails.logger.error $!
      Rails.logger.error $!.backtrace.join("\n")
      ExceptionNotifier.notify_exception($!, data: { message: error })
    end #while @page_with_orders.blank? == false || @page == 50
  end

  private


  def build_address_cz(city, zip)
    return nil if city.blank? && zip.blank?
    build_c = city.nil? ? "" : city + ", "
    build_z = zip.nil? ? "" : zip

    "#{build_c}#{build_z}"
  end

  def error_notification_params(error)
    {
      message: 'error_during_baqio_api_call',
      level: :error,
      target_type: '',
      target_url: '',
      interpolations: {
        error_message: error
      }
    }
  end
end
  