class BaqioFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  SALE_STATE = [
    { order_state: "draft", sale_state: :draft},
    { order_state: "pending", sale_state: :estimate},
    { order_state: "validated", sale_state: :order},
    { order_state: "removed", sale_state: :aborted},
    { order_state: "invoiced", sale_state: :invoice},
    { order_state: "cancelled", sale_state: :refused}
  ].freeze

  PRODUCT_CATEGORY_BAQIO = [
    { value: 1, category: "Vin tranquille" },
    { value: 2, category: "Vin mousseux" },
    { value: 3, category: "Cidre" },
    { value: 4, category: "VDN et VDL AOP" },
    { value: 5, category: "Bière" },
    { value: 6, category: "Boisson fermentée autre que le vin et la bière" },
    { value: 7, category: "Rhum des DOM" },
    { value: 8, category: "Autre produit intermédiaire que VDN et VDL AOP" },
    { value: 9, category: "Autre" },
    { value: 10, category: "Pétillant de raisin" },
    { value: 11, category: "Poiré" },
    { value: 12, category: "Hydromel" },
    { value: 13, category: "Alcool (autre que Rhum)" },
    { value: 14, category: "Pétillant de raisin" },
    { value: 15, category: "Rhums tiers (hors DOM) et autres rhums" },
    { value: 16, category: "Matière première pour alcool non alimentaire" },
    { value: 17, category: "Matière première pour spiritueux" }
  ].freeze

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

            # pn = ProductNature.find_by(reference_name: "wine") || ProductNature.import_from_nomenclature("wine")

            # pns = ProductNature.where("provider ->> 'id' = ?", family_product[:id].to_s)
            # if pns.any?
            #   pns.first
            # else
            #   new_pn = ProductNature.create!(
            #     name: family_product[:name],
            #     variety: pn.variety,
            #     derivative_of: pn.derivative_of,
            #     reference_name: pn.reference_name,
            #     active: pn.active,
            #     evolvable: pn.evolvable,
            #     population_counting: pn.population_counting,
            #     variable_indicators_list: [:certification, :reference_year, :temperature],
            #     frozen_indicators_list: pn.frozen_indicators_list,
            #     type: pn.type,
            #     provider: {vendor: "Baqio", name: "Baqio_product_family", id: family_product[:id]}
            #   )
            # end
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
            sales = Sale.where("provider ->> 'id' = ?", order[:id].to_s)
            if sales.any?
              sale = sales.first
            else
              if order[:id] == 133607 # || order[:id] == 133605
                # Create Variants from Baqio order_lines
                invoiced_date = order[:state] == "invoiced" ? order[:date] : nil
                confirmed_date = order[:state] == "validated" ? order[:date] : nil

                sale = Sale.create!(
                  client_id: entity.id,
                  provider: {vendor: "Baqio", name: "Baqio_order", id: order[:id]},
                  invoiced_at: invoiced_date,
                  confirmed_at: confirmed_date
                )

                sale.update!(state: sale_state_matching(order[:state]))
                sale.affair.refresh!

                # Find Tax Lines
                @tax_order = Tax.find_by(amount: order[:tax_lines].first[:tax_percentage])

                # Create SaleItem
                order[:order_lines_not_deleted].each do |product_order|

                  product_nature_variants = ProductNatureVariant.where("provider ->> 'id' = ?", product_order[:id].to_s)

                  binding.pry
                  if product_nature_variants.any?
                    product_nature_variant = product_nature_variants.first
                  else
                    binding.pry

                    # Find Baqio product_family_id and product_category_id
                    Baqio::BaqioIntegration.fetch_product_variants(product_order[:product_variant_id]).execute do |c|
                      c.success do |order|
                        @product_category_id = order["product"]["product_family_id"].to_s
                        @product_nature_id = order["product"]["product_category_id"].to_s
                      end
                    end

                    # Find or Create ProductNature from Baqio Product Type
                    pns = ProductNature.where("provider ->> 'id' = ?", @product_nature_id)
                    if pns.any?
                      product_nature = pns.first
                    else
                      pn = ProductNature.find_by(reference_name: "wine") || ProductNature.import_from_nomenclature("wine")

                      product_nature = ProductNature.create!(
                        name: product_category_baqio_matching(@product_nature_id.to_i),
                        variety: pn.variety,
                        derivative_of: pn.derivative_of,
                        reference_name: pn.reference_name,
                        active: pn.active,
                        evolvable: pn.evolvable,
                        population_counting: pn.population_counting,
                        variable_indicators_list: [:certification, :reference_year, :temperature],
                        frozen_indicators_list: pn.frozen_indicators_list,
                        type: pn.type,
                        provider: {vendor: "Baqio", name: "Baqio_product_type", id: @product_nature_id}
                      )
                    end

                    product_nature_category = ProductNatureCategory.find_by("provider ->> 'id' = ?", @product_category_id)

                    # Find or create new variant
                    product_nature_variant =  ProductNatureVariant.create!(
                      category_id: product_nature_category.id,
                      nature_id: product_nature.id,
                      name: "#{product_order[:name]} - #{product_order[:complement]} - #{product_order[:description]}",
                      unit_name: "Unité",
                      provider: {vendor: "Baqio", name: "Baqio_product_order", id: product_order[:id]}
                    )

                    sale_item = SaleItem.create!(
                      sale_id: sale.id,
                      variant_id: product_nature_variant.id,
                      label: "#{product_order[:name]} - #{product_order[:complement]} - #{product_order[:description]}",
                      currency: product_order[:price_currency],
                      quantity: product_order[:quantity].to_d,
                      unit_pretax_amount: (product_order[:price_cents] / 100.0).to_d,
                      tax_id: @tax_order.id
                    )
                  end
                end

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

  def product_category_baqio_matching(category_id)
    PRODUCT_CATEGORY_BAQIO.find {|h| h[:value] == category_id}[:category]
  end

  def sale_state_matching(order_state)
    SALE_STATE.find {|h| h[:order_state] == order_state}[:sale_state]
  end

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
  