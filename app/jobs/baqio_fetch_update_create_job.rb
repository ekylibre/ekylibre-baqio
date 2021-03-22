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

  BANK_ACCOUNT_PREFIX_NUMBER = "512"

  BAQIO_CASH_ACCOUNT_NUMBER = 531201

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
      create_or_update_cashe
      
      # TODO create or update incoming_payment_mode from baqio api
      create_or_update_incoming_payment_mode

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

  # TODO create or update cashes
  def create_or_update_cashe
    Baqio::BaqioIntegration.fetch_bank_informations.execute do |c|
      c.success do |list|
        list.map do |bank_information|
          iban = bank_information[:iban].gsub(/\s+/, "")
          cash = Cash.where(iban: iban)

          if cash.any?
            cash = cash.first
            # Check if Cash exist 
            # 
            # C)
            # If exist and provider is nil update it 
            if cash
            cash.update!(
              provider: { vendor: VENDOR, name: "Baqio_bank_information", data: { id: bank_information[:id].to_s, primary: bank_information[:primary]  } }
            )
            end

          else
            account = create_account(bank_information)
            journal = create_journal(bank_information, list)

            cash = Cash.create!(
              name: bank_information[:domiciliation],
              nature: "bank_account",
              mode: 'iban',
              iban: bank_information[:iban],
              journal_id: journal.id,
              main_account_id: account.id,
              provider: { vendor: VENDOR, name: "Baqio_bank_information", data: { id: bank_information[:id].to_s, primary: bank_information[:primary]  } }
            )
          end

        end
      end
    end
  end

  def create_journal(bank_information, list)
    bank_information_index = list.index(bank_information).to_s
    journal = Journal.create!(
      name: "Banque" + bank_information[:domiciliation],
      nature: "bank",
      code: "BQB" + bank_information_index,
      provider: { vendor: VENDOR, name: "Baqio_bank_information", data: { id: bank_information[:id].to_s, primary: bank_information[:primary]  } }
    )
  end

  def create_account(bank_information)
    # # Find all account with first 3 number BANK_ACCOUNT_PREFIX_NUMBER
    accounts = Account.select{|a| a.number.first(3) == BANK_ACCOUNT_PREFIX_NUMBER }

    # Check and compare all the following number if they are not 0
    array = []
    last_account_number_without_prefix =  accounts.each {|a| array << a.number[3].to_i}

    # Find the last one and add 1
    account_number_prefix = BANK_ACCOUNT_PREFIX_NUMBER + (array.max + 1).to_s
    account_number = Accountancy::AccountNumberNormalizer.build_deprecated_for_account_creation.normalize!(account_number_prefix)

    account = Account.create!(
      number: account_number,
      name: "Banque" + bank_information[:domiciliation],
      provider: { vendor: VENDOR, name: "Baqio_bank_information", data: { id: bank_information[:id].to_s, primary: bank_information[:primary] }}
    )
  end

  # Create or find Cash with cash_box nature
  def create_or_find_cash_box
    account_number = Accountancy::AccountNumberNormalizer.build_deprecated_for_account_creation.normalize!(BAQIO_CASH_ACCOUNT_NUMBER)
    cashes = Cash.cash_boxes.joins(:main_account).where(accounts: {number: account_number})

    if cashes.any?
      cashes.first
    else
      account = Account.create!(
        number: account_number,
        name: "Caisse Baqio"
      )
  
      journal = Journal.create!(
        name: "Caisse Baqio",
        nature: "cash",
        code: "BQC1"         
      )
  
      cash = Cash.create!(
        name: "Caisse Baqio",
        nature: "cash_box",
        journal_id: journal.id,
        main_account_id: account.id
      )
    end
  end

  # TODO create or update incoming_payment_mode from baqio api
  def create_or_update_incoming_payment_mode
    Baqio::BaqioIntegration.fetch_payment_sources.execute do |c|
      c.success do |list|
        list.select{ |c| c[:displayed] == true}.map do |incoming_payment_mode|
          incoming_payment_modes = IncomingPaymentMode.of_provider_vendor(VENDOR).of_provider_data(:id, incoming_payment_mode[:id].to_s)
          
          if incoming_payment_modes.any?
            incoming_payment_modes.first
          else
            # IF payment source == "Espèce" we need to use Cash "Caisse" or "Create it"
            if incoming_payment_mode[:name] == "Espèces"
              cash = create_or_find_cash_box
            else

              if incoming_payment_mode[:bank_information_id].nil?
                cash = Cash.of_provider_vendor(VENDOR).of_provider_data('primary', "true").first
              else
                cash = Cash.of_provider_vendor(VENDOR).of_provider_data(:id, incoming_payment_mode[:bank_information_id].to_s).first
              end
            end
            # TODO manage deposit with cash later
            unless cash.nil?
              incoming_payment_mode = IncomingPaymentMode.create!(
                name: incoming_payment_mode[:name],
                cash_id: cash.id,
                active: true,
                with_accounting: true,
                with_deposit: false,
                provider: { vendor: VENDOR, name: "Baqio_payment_source", data: {id: incoming_payment_mode[:id].to_s, bank_information_id: incoming_payment_mode[:bank_information_id].to_s} }
              )
            end
          end
        end
      end
    end
  end


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
      if order[:id] == 133607 #|| order[:id] == 133591 #|| order[:id] == 133605 || order[:id] == 133591
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

      binding.pry
      order[:order_lines_not_deleted].each do |product_order|
        create_or_update_sale_items(sale, product_order, order)
      end

      binding.pry
      sale.update!(provider: { vendor: VENDOR, name: "Baqio_order", data: {id: order[:id].to_s, updated_at: order[:updated_at]} })
      # if order[:payment_status] == "paid"
      #   # If order is Update delete all sale items and create new sale items
      #   unless sale.provider[:data]["updated_at"] == order[:updated_at]
      #     # Delete all sales items and create new one
      #     sale.items.destroy_all

      #     order[:order_lines_not_deleted].each do |product_order|
      #       create_sale_items(sale, product_order, order)
      #     end

      #     order[:payment_links].each do |payment_link|
      #       create_incoming_payment(sale, payment_link[:payment][:payment_source_id].to_s)
      #     end
  
      #     sale.save!
      #   end
      # end

    else
      # TO REMOVE later / Create only 2 orders for testing
      if order[:id] == 133607 #|| order[:id] == 133591 #|| order[:id] == 133605
        # Check and define the state's sale
        invoiced_date = order[:state] == "invoiced" ? order[:date] : nil
        confirmed_date = order[:state] == "validated" ? order[:date] : nil

        sale = Sale.new(
          client_id: entity.id,
          reference_number: nil, # TODO add invoice number from Baqio
          provider: { vendor: VENDOR, name: "Baqio_order", data: {id: order[:id].to_s, updated_at: order[:updated_at]} },
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
        # sale.invoice(sale.invoiced_at) if SALE_STATE[order[:state]] == :invoice
        # sale.invoice(sale.invoiced_at) if SALE_STATE[order[:state]] == :invoice

        # sale.propose if sale.draft?
        # sale.confirm(sale.invoiced_at)
        # sale.invoice(sale.invoiced_at)
        
        # TODO link baqio pdf to sale
        attach_pdf_to_sale(sale, order[:invoice_debit][:file_url].to_s, order[:invoice_debit][:name])

        sale
      end
    end
  end

  def create_incoming_payment(sale, incoming_payment_mode_id)
    mode = IncomingPaymentMode.of_provider_vendor(VENDOR).of_provider_data(:id, incoming_payment_mode_id).first

    incoming_payment = IncomingPayment.create!(
      journal_entry_id: sale.journal_entry.id,
      affair_id: sale.affair.id,
      amount: sale.amount,
      currency: sale.currency,
      mode_id: mode.id,
      payer: sale.client
    )
  end

  def create_or_update_sale_items(sale, product_order, order)
    tax_order = Tax.find_by(amount: order[:tax_lines].first[:tax_percentage])
    variant = find_or_create_variant(product_order)
    
    if sale.nil?
      binding.pry
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
    else
      SaleItem.create!(
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

  def attach_pdf_to_sale(sale, file_url, invoice_name)
    unless file_url.nil?
      doc = Document.new(file: URI.open(file_url), name: invoice_name, file_file_name: invoice_name + ".pdf")
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