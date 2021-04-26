# frozen_string_literal: true

class BaqioFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  VENDOR = 'baqio'

  # SALTE_STATE "cancelled" is invoice, need to be change to V2 
  SALE_STATE = {
    "draft" => :draft, "pending" => :estimate,
    "validated" => :order, "removed" => :aborted,
    "invoiced" => :invoice, "cancelled" => :invoice
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

  BAQIO_TAX_TYPE_TO_EKY = {
    "standard" => "normal_vat", "intermediate" => "intermediate_vat", 
    "reduced" => "reduced_vat", "exceptional" => "particular_vat"
  }

  CATEGORY = "wine"

  BANK_ACCOUNT_PREFIX_NUMBER = "512201"

  BAQIO_CASH_ACCOUNT_NUMBER = 531201

  def perform
    # Page need to be set-up to fetch orders from different Baqio pages
    @page = 0

    # Set page_with_ordres to ended the job if orders page is blank
    @page_with_orders = []

    @init_product_nature = ProductNature.find_by(reference_name: CATEGORY) || ProductNature.import_from_nomenclature(CATEGORY)

    begin
      # Create ProductNatureCategory and ProductNature from Baqio product_families
      pnc_handler = Integrations::Baqio::Handlers::ProductNatureCategories.new(vendor: VENDOR, category: CATEGORY)
      pnc_handler.bulk_find_or_create

      # TODO call create or update cashes from baqio api
      cash_handler = Integrations::Baqio::Handlers::Cashes.new(vendor: VENDOR, bank_account_prefix_number: BANK_ACCOUNT_PREFIX_NUMBER)
      cash_handler.bulk_find_or_create

      # TODO create or update incoming_payment_mode from baqio api
      incoming_payment_mode_handler = Integrations::Baqio::Handlers::IncomingPaymentModes.new(vendor: VENDOR)
      incoming_payment_mode_handler.bulk_find_or_create

      # Create sales from baqio order's @page +=1)
      Baqio::BaqioIntegration.fetch_orders(@page +=1).execute do |c|
        c.success do |list|
          @page_with_orders = list

          max_date = FinancialYear.where(state: "opened").map{ |date| date.stopped_on.to_time }
          min_date = FinancialYear.where(state: "opened").map{ |date| date.started_on.to_time }
          # select only order with date located in opened financial year

          list.select{ |order| max_date.max > order[:date].to_time && order[:date].to_time > min_date.min }.map do |order|
            entity = find_or_create_entity(order)
            create_or_update_sale(order, entity)
          end
        end
      end

    rescue StandardError => error
      Rails.logger.error $!
      Rails.logger.error $!.backtrace.join("\n")
      ExceptionNotifier.notify_exception($!, data: { message: error })
    end while @page_with_orders.blank? == false || @page == 50
  end

  private

  def find_or_create_entity(order)
    entities = Entity.of_provider_vendor(VENDOR).of_provider_data(:id, order[:customer][:id].to_s)
    if entities.any?
      entity = entities.first
    else
      # TO REMOVE later / Create only 2 orders for testing
        custom_name = if order[:customer][:billing_information][:last_name].nil?
                        order[:customer][:billing_information][:company_name]
                      else
                        order[:customer][:name]
                      end
        # TODO check and add custom nature (ex: Customer "Particulier" at Baqio become "Contact" nature at Ekylibre)
        # Need API update from Baqio, method customer/id doesn't work
        entity = Entity.create!(
          first_name: order[:customer][:billing_information][:first_name],
          last_name: custom_name,
          client: true,
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

  def create_or_update_sale(order, entity)
    sales = Sale.of_provider_vendor(VENDOR).of_provider_data(:id, order[:id].to_s)

    if sales.any?
      sale = sales.first
      # Update sale if sale provider updated_at is different from Baqio order[:updated_at] and Baqio order[:state] is in the SALE_STATE_TO_UPDATE
      if sale.provider[:data]["updated_at"] != order[:updated_at] && sale.state != SALE_STATE[order[:state]] && sale.state != "invoice"
        # Delete all sales items and create new one
        sale.items.destroy_all

        order[:order_lines_not_deleted].each do |product_order|
          create_or_update_sale_items(sale, product_order, order)
        end

        # Create shipping_line SaleItem when shipping_line[:price_cents] is present
        if order[:shipping_line][:price_cents] > 0
          create_shipping_line_sale_item(sale, order[:shipping_line], order)
        end

        # Update sale provider with new updated_at
        sale.provider = { vendor: VENDOR, name: "Baqio_order", data: {id: order[:id].to_s, updated_at: order[:updated_at]} }
        sale.reference_number = order[:invoice_debit][:name] if SALE_STATE[order[:state]] == :invoice
        sale.save!
        
        update_sale_state(sale, order)

        attach_pdf_to_sale(sale, order[:invoice_debit]) if SALE_STATE[order[:state]] == :invoice

      end

      # Update or Create incocoming payment
      order[:payment_links].each do |payment_link|
        create_update_or_delete_incoming_payment(sale, payment_link)
      end

      # Cancel sale and attach invoice_credit
      cancel_and_create_sale_credit(sale, order)
 
    else
      # TO REMOVE later / Create only 2 orders for testing
      sale = Sale.new(
        client_id: entity.id,
        reference_number: order[:name], # TODO add invoice number from Baqio
        provider: { vendor: VENDOR, name: "Baqio_order", data: {id: order[:id].to_s, updated_at: order[:updated_at]} },
      )
      
      # Create SaleItem if order[:order_lines_not_deleted] is not nil
      order[:order_lines_not_deleted].each do |product_order|
        if !product_order.nil?
          create_or_update_sale_items(sale, product_order, order)
        end
      end

      # Create shipping_line SaleItem when shipping_line[:price_cents] is present
      if order[:shipping_line][:price_cents] > 0
        create_shipping_line_sale_item(sale, order[:shipping_line], order)
      end

      sale.save!
      sale.update!(created_at: order[:created_at].to_time)
      sale.update!(reference_number: order[:invoice_debit][:name]) if SALE_STATE[order[:state]] == :invoice

      update_sale_state(sale, order)

      attach_pdf_to_sale(sale, order[:invoice_debit])

      # Update or Create incocoming payment
      order[:payment_links].each do |payment_link|
        create_update_or_delete_incoming_payment(sale, payment_link)
      end

      # Cancel sale and attach invoice_credit
      cancel_and_create_sale_credit(sale, order)

      sale
    end
  end

  def create_update_or_delete_incoming_payment(sale, payment_link)
    mode = IncomingPaymentMode.of_provider_vendor(VENDOR).of_provider_data(:id, payment_link[:payment][:payment_source_id].to_s).first
    incoming_payment = IncomingPayment.of_provider_vendor(VENDOR).of_provider_data(:id, payment_link[:payment][:id].to_s).first

    baqio_payment_amount = payment_link[:payment][:amount_cents].to_d * 0.01
    baqio_payment_date = Date.parse(payment_link[:payment][:date].to_s).to_time
    baqio_payment_currency = payment_link[:payment][:amount_currency]

    # Update if incoming_payment exist AND if payment_link[:payment][:deleted_at] is nil
    if incoming_payment && payment_link[:payment][:deleted_at].nil?
      # update incoming payment attrs
      incoming_payment.paid_at = baqio_payment_date
      incoming_payment.to_bank_at = baqio_payment_date
      incoming_payment.amount = baqio_payment_amount
      incoming_payment.currency = baqio_payment_currency
      incoming_payment.save!
    end

    # Delete if incoming_payment exist AND if payment_link[:payment][:deleted_at] is present (date)
    if incoming_payment && payment_link[:payment][:deleted_at].present?
      incoming_payment.destroy
    end

    # Create if incoming_payment doesn't exist AND if payment_link[:payment][:deleted_at] is nil
    if incoming_payment.nil? && payment_link[:payment][:deleted_at].nil?
      incoming_payment = IncomingPayment.create!(
        affair_id: sale.affair.id,
        amount: baqio_payment_amount,
        currency: baqio_payment_currency,
        mode_id: mode.id,
        payer: sale.client,
        paid_at: baqio_payment_date,
        to_bank_at: baqio_payment_date,
        provider: { vendor: VENDOR, name: "Baqio_payment", data: {id: payment_link[:payment][:id]} }
      )
    end

    # TODO LATER detach affaire
  end

  def create_or_update_sale_items(sale, product_order, order)
    eky_tax = find_baqio_tax_to_eky(product_order, order)
    variant = find_or_create_variant(product_order)
    reduction_percentage = product_order[:total_discount_cents] == 0 ? 0 : (product_order[:total_discount_cents].to_f /  product_order[:final_price_cents].to_f) * 100

    sale.items.build(
      sale_id: sale.id,
      variant_id: variant.id,
      label: "#{product_order[:name]} - #{product_order[:complement]} - #{product_order[:description]}",
      currency: product_order[:price_currency],
      quantity: product_order[:quantity].to_d,
      reduction_percentage: reduction_percentage,
      pretax_amount: (product_order[:final_price_cents] / 100.0).to_d,
      amount: (product_order[:final_price_with_tax_cents] / 100.0).to_d,
      compute_from: "pretax_amount",
      tax_id: eky_tax.id
    )
  end

  def find_baqio_tax_to_eky(product_order, order)
    if product_order[:tax_lines].present?
      find_baqio_country_tax(product_order[:tax_lines])
      return Tax.find_by(country: @country_tax_code, amount: @country_tax_percentage, nature: @country_tax_type)

    elsif order[:accounting_tax] == 'fr' && !product_order[:tax_lines].present? && order[:tax_lines].present?
      find_baqio_country_tax(order[:tax_lines])
      return Tax.find_by(country: @country_tax_code, amount: @country_tax_percentage, nature: @country_tax_type)

    elsif order[:accounting_tax] == 'fr' && !product_order[:tax_lines].present? && !order[:tax_lines].present?
      return Tax.find_by(nature: "null_vat")

    else
      return Tax.find_by(nature: 'eu_vat', amount: 0.0) if order[:accounting_tax] == 'eu'
      return Tax.find_by(nature: 'import_export_vat', amount: 0.0) if order[:accounting_tax] == 'world'
    end 
  end

  def find_baqio_country_tax(tax_line)
    country_tax_id = tax_line.first[:country_tax_id].to_i

    country_tax_baqio = Baqio::BaqioIntegration.fetch_country_taxes.execute do |c|
                          c.success do |list|
                            list.select{ |ct| ct[:id] == country_tax_id}.map do |country_tax|
                              country_tax
                            end
                          end
                        end

    @country_tax_code = country_tax_baqio.first[:code].downcase
    @country_tax_percentage = country_tax_baqio.first[:tax_percentage].to_f
    @country_tax_type = BAQIO_TAX_TYPE_TO_EKY[country_tax_baqio.first[:tax_type]]
  end

  def create_shipping_line_sale_item(sale, shipping_line, order)
    shipping_line_tax_price_cents = shipping_line[:price_with_tax_cents] - shipping_line[:price_cents]
    # Find shipping_line tax_line throught order[:tax_line] with price_cents
    shipping_line_tax_line = order[:tax_lines].select {|t| t[:price_cents] == shipping_line_tax_price_cents }

    eky_tax = if shipping_line_tax_line.present?
                find_baqio_country_tax(shipping_line_tax_line)
                Tax.find_by(country: @country_tax_code, amount: @country_tax_percentage, nature: @country_tax_type)
              else
                Tax.find_by(nature: "null_vat")
              end
    
    variant = ProductNatureVariant.import_from_nomenclature(:carriage)

    sale.items.build(
      sale_id: sale.id,
      variant_id: variant.id,
      label: "#{shipping_line[:name]}",
      currency: shipping_line[:price_currency],
      quantity: 1,
      unit_pretax_amount: (shipping_line[:price_cents] / 100.0).to_d,
      pretax_amount: (shipping_line[:price_cents] / 100.0).to_d,
      amount: (shipping_line[:price_with_tax_cents] / 100.0).to_d,
      compute_from: "amount",
      tax_id: eky_tax.id
    )
  end

  def update_sale_state(sale, order)
    order_date = Date.parse(order[:date]).to_time

    sale.correct if SALE_STATE[order[:state]] == :aborted || :estimate
    sale.propose if SALE_STATE[order[:state]] == :estimate || sale.items.present?
    sale.abort if SALE_STATE[order[:state]] == :aborted
    sale.confirm(order_date) if SALE_STATE[order[:state]] == :order
    sale.invoice(order_date) if SALE_STATE[order[:state]] == :invoice
  end

  def cancel_and_create_sale_credit(sale, order)
    if sale.credits.empty? && order[:state] == "cancelled"
      sale_credit = sale.build_credit
      sale_credit.reference_number = order[:invoice_credit][:name]
      sale_credit.provider = { 
                              vendor: VENDOR, 
                              name: "Baqio_order_invoice_credit", 
                              data: { id: order[:invoice_credit][:id], order_id: order[:invoice_credit][:order_id] } 
                              }
      sale_credit.save!
      sale_credit.update!(created_at: order[:invoice_credit][:created_at].to_time)
      sale_credit.invoice!

      attach_pdf_to_sale(sale_credit, order[:invoice_credit])
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

  def attach_pdf_to_sale(sale, order_invoice)
    if !order_invoice.nil?
      doc = Document.new(file: URI.open(order_invoice[:file_url].to_s), name: order_invoice[:name], file_file_name: order_invoice[:name] + ".pdf")
      sale.attachments.create!(document: doc)
    end
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
