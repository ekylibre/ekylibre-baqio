# frozen_string_literal: true

class BaqioFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  VENDOR = 'baqio'

  SALE_STATE = {
    "draft" => :draft, "pending" => :estimate,
    "validated" => :order, "removed" => :aborted,
    "invoiced" => :invoice, "cancelled" => :refused
  }

  PRODUCT_CATEGORY_BAQIO = {
    1 => "Vin tranquille", 2 => "Vin mousseux", 3 => "Cidre",
    4 => "VDN et VDL AOP", 5 => "Bière", 6 => "Boisson fermentée autre que le vin et la bière",
    7 => "Rhum des DOM", 8 => "Autre produit intermédiaire que VDN et VDL AOP", 9 => "Autre",
    10 => "Pétillant de raisin", 11 => "Poiré", 12 => "Hydromel",
    13 => "Alcool (autre que Rhum)", 14 => "Pétillant de raisin",
    15  => "Rhums tiers (hors DOM) et autres rhums", 16  => "Matière première pour alcool non alimentaire",
    17  => "Matière première pour spiritueux"
  }

  CATEGORY = "wine"

  def perform
    # Page need to be set-up to fetch orders from different Baqio pages
    @page = 0

    # Set page_with_ordres to ended the job if orders page is blank
    @page_with_orders = []

    @init_category = ProductNatureCategory.find_by(reference_name: CATEGORY) || ProductNatureCategory.import_from_nomenclature(CATEGORY)

    @init_product_nature = ProductNature.find_by(reference_name: CATEGORY) || ProductNature.import_from_nomenclature(CATEGORY)

    begin
      # Create ProductNatureCategory and ProductNature from Baqio product_families
      find_or_create_product_nature_category

      # TODO call create or update cashes from baqio api

      # TODO create or update incoming_payment_mode from baqio api

      # Create sales from baqio order's @page +=1)
      Baqio::BaqioIntegration.fetch_orders(1).execute do |c|
        c.success do |list|
          @page_with_orders = list
          list.map do |order|
            entity = find_or_create_entity(order)
            find_or_create_sale(order, entity)
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

  def find_or_create_product_nature_category
    Baqio::BaqioIntegration.fetch_family_product.execute do |c|
      c.success do |list|
        list.map do |family_product|

          product_nature_categories = ProductNatureCategory.of_provider_vendor(VENDOR).of_provider_data(:id, family_product[:id].to_s)

          if product_nature_categories.any?
            product_nature_categories.first
          else
            product_nature_category = ProductNatureCategory.find_or_initialize_by(name: family_product[:name])

            product_nature_category.pictogram = @init_category.pictogram
            product_nature_category.active = family_product[:displayed]
            product_nature_category.depreciable = @init_category.depreciable
            product_nature_category.saleable = @init_category.saleable
            product_nature_category.purchasable = @init_category.purchasable
            product_nature_category.storable = @init_category.storable
            product_nature_category.reductible = @init_category.reductible
            product_nature_category.subscribing = @init_category.subscribing
            product_nature_category.product_account_id = @init_category.product_account_id
            product_nature_category.stock_account_id = @init_category.stock_account_id
            product_nature_category.fixed_asset_depreciation_percentage = @init_category.fixed_asset_depreciation_percentage
            product_nature_category.fixed_asset_depreciation_method = @init_category.fixed_asset_depreciation_method
            product_nature_category.stock_movement_account_id = @init_category.stock_movement_account_id
            product_nature_category.type = @init_category.type
            product_nature_category.provider = { vendor: VENDOR, name: "Baqio_product_family", data: {id: family_product[:id].to_s} }

            product_nature_category.save!
          end
        end
      end
    end
  end

  def find_or_create_entity(order)
    entities = Entity.of_provider_vendor(VENDOR).of_provider_data(:id, order[:customer][:id].to_s)
    if entities.any?
      entity = entities.first
    else
      # TO REMOVE later / Create only 2 orders for testing
      if order[:id] == 133607 #|| order[:id] == 133605 || order[:id] == 133591
        binding.pry
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
          provider: {
                    vendor: VENDOR,
                    name: "Baqio_order_customer",
                    data: { id: order[:customer][:id].to_s }
                    }
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

        entity
      end
    end
  end

  def find_or_create_sale(order, entity)
    sales = Sale.of_provider_vendor(VENDOR).of_provider_data(:id, order[:id].to_s)
    if sales.any?
      sale = sales.first

      # binding.pry
      # if order[:payment_status] == "paid"
      #   # TODO check_or_create_incoming_payment
      #   incoming_payment = IncomingPayment.create!(
      #     journal_entry_id: sale.journal_entry.id,
      #     affair_id: sale.affair.id,
      #     amount: sale.amount,
      #     currency: sale.currency,
      #     mode_id: 2,
      #     payer: sale.client
      #   )
      # end


      # Carte Bancaire, Espèces, Chèque, Virement Bancaire => credit_card, cash, check, transfer order[:payment_links].first[:payment][:payment_source][:handle]
    else
      # TO REMOVE later / Create only 2 orders for testing
      if order[:id] == 133607 #|| order[:id] == 133605 || order[:id] == 133591
        # Check and define the state's sale
        invoiced_date = order[:state] == "invoiced" ? order[:date] : nil
        confirmed_date = order[:state] == "validated" ? order[:date] : nil

        binding.pry

        sale = Sale.new(
          client_id: entity.id,
          reference_number: nil, # TODO add invoice number from Baqio
          provider: { vendor: VENDOR, name: "Baqio_order", data: {id: order[:id].to_s} },
          invoiced_at: invoiced_date,
          confirmed_at: confirmed_date
        )

        tax_order = Tax.find_by(amount: order[:tax_lines].first[:tax_percentage])

        # Create SaleItem
        order[:order_lines_not_deleted].each do |product_order|
          variant = find_or_create_variant(product_order)

          sale.items.build(
            sale_id: sale.id,
            variant_id: variant.id,
            label: "#{product_order[:name]} - #{product_order[:complement]} - #{product_order[:description]}",
            currency: product_order[:price_currency],
            quantity: product_order[:quantity].to_d,
            pretax_amount: (product_order[:total_price_cents] / 100.0).to_d,
            compute_from: "pretax_amount",
            tax_id: tax_order.id
          )
        end

        sale.save!

        # TODO update status of sale from baqio status
        sale.update!(state: SALE_STATE[order[:state]])
        # sale.invoice(sale.invoiced_at) if SALE_STATE[order[:state]] == :invoice

        # TODO link baqio pdf to sale
        # attach_pdf_to_sale(sale, order[:invoice_debit][:file][:url].to_s)

        sale
      end
    end
  end

  def fetch_product_family_and_category_id(product_variant_id)
    Baqio::BaqioIntegration.fetch_product_variants(product_variant_id).execute do |c|
      c.success do |order|
        @product_category_id = order["product"]["product_family_id"].to_s
        @product_nature_id = order["product"]["product_category_id"].to_s
      end
    end
  end

  def find_or_create_product_nature(product_nature_id)
    pns = ProductNature.of_provider_vendor(VENDOR).of_provider_data(:id, product_nature_id.to_s)

    if pns.any?
      product_nature = pns.first
    else
      product_nature = ProductNature.find_or_initialize_by(name: PRODUCT_CATEGORY_BAQIO[product_nature_id.to_i])

      product_nature.variety = @init_product_nature.variety
      product_nature.derivative_of = @init_product_nature.derivative_of
      product_nature.reference_name = @init_product_nature.reference_name
      product_nature.active = @init_product_nature.active
      product_nature.evolvable = @init_product_nature.evolvable
      product_nature.population_counting = @init_product_nature.population_counting
      product_nature.variable_indicators_list = [:certification, :reference_year, :temperature]
      product_nature.frozen_indicators_list = @init_product_nature.frozen_indicators_list
      product_nature.type = @init_product_nature.type
      product_nature.provider = { vendor: VENDOR, name: "Baqio_product_type", data: {id: product_nature_id.to_s} }
      product_nature.save!

      product_nature
    end
  end

  def find_or_create_variant(product_order)
    product_nature_variants = ProductNatureVariant.of_provider_vendor(VENDOR).of_provider_data(:id, product_order[:product_variant_id].to_s)

    if product_nature_variants.any?
      product_nature_variant = product_nature_variants.first
    else
      # Find Baqio product_family_id and product_category_id to find product nature and product category at Ekylibre
      fetch_product_family_and_category_id(product_order[:product_variant_id])
      product_nature = find_or_create_product_nature(@product_nature_id)
      product_nature_category = ProductNatureCategory.of_provider_vendor(VENDOR).of_provider_data(:id, @product_category_id).first

      # Find or create new variant
      product_nature_variant =  ProductNatureVariant.create!(
        category_id: product_nature_category.id,
        nature_id: product_nature.id,
        name: "#{product_order[:name]} - #{product_order[:complement]} - #{product_order[:description]}",
        unit_name: "Unité",
        provider: { vendor: VENDOR, name: "Baqio_product_order", data: {id: product_order[:product_variant_id].to_s} }      )
    end
  end

  def attach_pdf_to_sale(sale, file_url)
    # TODO check if url return a file
    doc = Document.new(file: File.open(file_url))
    sale.attachments.create!(document: doc)
  end

  # TODO create or update incoming_payment_mode from baqio api

  # TODO create or update cashes

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
