# frozen_string_literal: true

module Integrations
  module Baqio 
    module Handlers
      class Sales

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

        def initialize(vendor:, category: category)
          @vendor = vendor
          @category = category
          @init_product_nature = ProductNature.find_by(reference_name: @category) || ProductNature.import_from_nomenclature(@category)
        end

        def bulk_find_or_create
          @page = 0

          loop do 
            data_orders = Integrations::Baqio::Data::Orders.new(@page +=1).result

            data_orders.each do |order|
              if order[:id] == 231340
                next if find_and_update_existant_sale(order).present?

                entity = find_or_create_entity(@vendor, order[:customer])
                create_sale(order, entity)
              end

            end

            break if data_orders.blank? || @page == 50  
          end

        end

        private 

        def find_and_update_existant_sale(order)
          sale = Sale.of_provider_vendor(@vendor).of_provider_data(:id, order[:id].to_s).first

          if sale.present?
            update_existant_sale(sale, order)
          end

          sale
        end

        def update_existant_sale(sale, order)
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
            sale.provider = { vendor: @vendor, name: "Baqio_order", data: {id: order[:id].to_s, updated_at: order[:updated_at]} }
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
        end

        def create_sale(order, entity)
          # TO REMOVE later / Create only 2 orders for testing
          sale = Sale.new(
            client_id: entity.id,
            reference_number: order[:name], # TODO add invoice number from Baqio
            provider: { vendor: @vendor, name: "Baqio_order", data: {id: order[:id].to_s, updated_at: order[:updated_at]} },
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
      
          country_tax_baqio = ::Baqio::BaqioIntegration.fetch_country_taxes.execute do |c|
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

        def find_or_create_variant(product_order)
          product_nature_variants = ProductNatureVariant.of_provider_vendor(@vendor).of_provider_data(:id, product_order[:product_variant_id].to_s)
      
          if product_nature_variants.any?
            product_nature_variant = product_nature_variants.first
          else
            # Find Baqio product_family_id and product_category_id to find product nature and product category at Ekylibre
            fetch_product_family_and_category_id(product_order[:product_variant_id])
            product_nature = find_or_create_product_nature(@product_nature_id)
            product_nature_category = ProductNatureCategory.of_provider_vendor(@vendor).of_provider_data(:id, @product_category_id).first
      
            # Find or create new variant
            product_nature_variant =  ProductNatureVariant.create!(
              category_id: product_nature_category.id,
              nature_id: product_nature.id,
              name: "#{product_order[:name]} - #{product_order[:complement]} - #{product_order[:description]}",
              unit_name: "Unité",
              provider: { vendor: @vendor, name: "Baqio_product_order", data: {id: product_order[:product_variant_id].to_s} }      )
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
          binding.pry
          order_date = Date.parse(order[:date]).to_time
      
          sale.correct if SALE_STATE[order[:state]] == :aborted || :estimate
          sale.propose if SALE_STATE[order[:state]] == :estimate || sale.items.present?
          sale.abort if SALE_STATE[order[:state]] == :aborted
          sale.confirm(order_date) if SALE_STATE[order[:state]] == :order
          sale.invoice(order_date) if SALE_STATE[order[:state]] == :invoice
        end

        def attach_pdf_to_sale(sale, order_invoice)
          if !order_invoice.nil?
            doc = Document.new(file: URI.open(order_invoice[:file_url].to_s), name: order_invoice[:name], file_file_name: order_invoice[:name] + ".pdf")
            sale.attachments.create!(document: doc)
          end
        end

        def create_update_or_delete_incoming_payment(sale, payment_link)
          mode = IncomingPaymentMode.of_provider_vendor(@vendor).of_provider_data(:id, payment_link[:payment][:payment_source_id].to_s).first
          incoming_payment = IncomingPayment.of_provider_vendor(@vendor).of_provider_data(:id, payment_link[:payment][:id].to_s).first
      
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
              provider: { vendor: @vendor, name: "Baqio_payment", data: {id: payment_link[:payment][:id]} }
            )
          end
      
          # TODO LATER detach affaire
        end

        def cancel_and_create_sale_credit(sale, order)
          if sale.credits.empty? && order[:state] == "cancelled"
            sale_credit = sale.build_credit
            sale_credit.reference_number = order[:invoice_credit][:name]
            sale_credit.provider = { 
                                    vendor: @vendor, 
                                    name: "Baqio_order_invoice_credit", 
                                    data: { id: order[:invoice_credit][:id], order_id: order[:invoice_credit][:order_id] } 
                                    }
            sale_credit.save!
            sale_credit.update!(created_at: order[:invoice_credit][:created_at].to_time)
            sale_credit.invoice!
      
            attach_pdf_to_sale(sale_credit, order[:invoice_credit])
          end
        end

        def find_or_create_entity(vendor, order_customer)
          entity = Integrations::Baqio::Handlers::Entities.new(vendor: vendor, order_customer: order_customer)
          entity.bulk_find_or_create
        end

      end
    end
  end
end