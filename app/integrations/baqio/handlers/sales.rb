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

        def initialize(vendor:)
          @vendor = vendor
        end

        def bulk_find_or_create
          @page = 0

          loop do 
            data_orders = Integrations::Baqio::Data::Orders.new(@page +=1).result

            data_orders.each do |order|
              if order[:id] == 233028
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
            
            sale_items = Integrations::Baqio::Handlers::SaleItems.new(vendor: @vendor, sale: sale, order: order)
            sale_items.bulk_find_or_create
            sale_items.bulk_create_shipping_line_sale_item
    
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
          sale_items = Integrations::Baqio::Handlers::SaleItems.new(vendor: @vendor, sale: sale, order: order)
          sale_items.bulk_find_or_create
          sale_items.bulk_create_shipping_line_sale_item

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