# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class Sales

        BQ_STATE = {
          draft: :draft,
          pending: :estimate,
          validated: :order,
          removed: :aborted,
          invoiced: :invoice,
          cancelled: :invoice
        }.freeze

        def initialize(vendor:)
          @vendor = vendor
        end

        def bulk_find_or_create
          @page = 0

          loop do
            data_orders = Integrations::Baqio::Data::Orders.new(@page +=1).result.compact

            data_orders.each do |order|
              next if order[:state] == ('pending' || 'draft')
              next if find_and_update_existant_sale(order).present?

              if order[:order_lines_not_deleted].present? && order[:state] != 'cancelled'
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

            if sale.present? && order[:order_lines_not_deleted].present?
              update_existant_sale(sale, order)
            end

            sale
          end

          def update_existant_sale(sale, order)
            baqio_sale_state = BQ_STATE[order[:state].to_sym]

            if sale.state != baqio_sale_state && sale.state != 'invoice'
              # Delete all sale items and create new sale items
              sale.items.destroy_all
              create_sale_items(sale, order)
              # Update sale provider with new updated_at
              sale.provider = { vendor: @vendor, name: 'Baqio_order', data: { id: order[:id].to_s, updated_at: order[:updated_at] } }
              sale.reference_number = order[:invoice_debit][:name] if baqio_sale_state == :invoice
              sale.save!

              update_sale_state(sale, order)
              attach_pdf_to_sale(sale, order[:invoice_debit]) if baqio_sale_state == :invoice
            end

            create_update_or_delete_incoming_payments(sale, order)
            cancel_and_create_sale_credit(sale, order)
          end

          def create_sale(order, entity)
            sale = Sale.new(
              client_id: entity.id,
              reference_number: order[:name],
              provider: { vendor: @vendor, name: 'Baqio_order', data: { id: order[:id].to_s, updated_at: order[:updated_at] } },
            )

            create_sale_items(sale, order)
            sale.save!
            sale.update!(created_at: order[:created_at].to_time)
            sale.update!(reference_number: order[:invoice_debit][:name]) if BQ_STATE[order[:state].to_sym] == :invoice

            update_sale_state(sale, order)
            attach_pdf_to_sale(sale, order[:invoice_debit])

            create_update_or_delete_incoming_payments(sale, order)
            cancel_and_create_sale_credit(sale, order)

            sale
          end

          def create_sale_items(sale, order)
            sale_items = Integrations::Baqio::Handlers::SaleItems.new(vendor: @vendor, sale: sale, order: order)
            sale_items.bulk_create
            sale_items.bulk_create_shipping_line_sale_item
          end

          def create_update_or_delete_incoming_payments(sale, order)
            incoming_payments = Integrations::Baqio::Handlers::IncomingPayments.new(vendor: @vendor, sale: sale, order: order)
            incoming_payments.bulk_create_update_or_delete
          end

          def update_sale_state(sale, order)
            order_date = Date.parse(order[:date]).to_time
            baqio_sale_state = BQ_STATE[order[:state].to_sym]

            sale.correct if baqio_sale_state == :aborted
            sale.correct if baqio_sale_state == :estimate
            sale.propose if baqio_sale_state == :estimate || sale.items.present?
            sale.abort if baqio_sale_state == :aborted
            sale.confirm(order_date) if baqio_sale_state == :order
            sale.invoice(order_date) if baqio_sale_state == :invoice
          end

          def attach_pdf_to_sale(sale, order_invoice)
            if order_invoice.present? && order_invoice[:file_url].present? && order_invoice[:name].present?
              doc = Document.new(file: URI.parse(order_invoice[:file_url].to_s).open, name: order_invoice[:name],
  file_file_name: order_invoice[:name] + '.pdf')
              sale.attachments.create!(document: doc)
            end
          end

          def cancel_and_create_sale_credit(sale, order)
            if sale.credits.empty? && order[:state] == 'cancelled' && !order[:total_price_cents].zero?
              sale_credit = sale.build_credit
              sale_credit.reference_number = order[:invoice_credit][:name]
              sale_credit.provider = {
                                      vendor: @vendor,
                                      name: 'Baqio_order_invoice_credit',
                                      data: { id: order[:invoice_credit][:id], order_id: order[:invoice_credit][:order_id] }
                                      }
              sale_credit.save!
              invoiced_date = order[:invoice_credit][:created_at].to_time
              sale_credit.update!(created_at: invoiced_date, confirmed_at: invoiced_date, invoiced_at: invoiced_date)
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
