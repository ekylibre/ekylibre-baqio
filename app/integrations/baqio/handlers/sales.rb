# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class Sales

        attr_accessor :created, :updated, :last_sale_number_created

        BQ_STATE = {
          draft: :draft,
          pending: :estimate,
          validated: :order,
          removed: :aborted,
          invoiced: :invoice,
          cancelled: :invoice
        }.freeze

        def initialize(vendor:, user_id:, min_date:, max_date:)
          @vendor = vendor
          @user_id = user_id
          @count_created = 0
          @count_updated = 0
          @last_sale_number = nil
          @min_date = min_date
          @max_date = max_date
        end

        def bulk_find_or_create
          @page = 0

          loop do
            data_orders = Integrations::Baqio::Data::Orders.new(@page +=1, @user_id, @min_date, @max_date).result.compact

            data_orders.each do |order|
              next if order[:state] == ('pending' || 'draft')

              next if (order[:state] == 'removed' && order[:customer].nil? && order[:receipt_debit].nil? && order[:invoice_debit].nil?)

              next if (order[:invoice_debit].present? && FinancialYear.on(Date.parse(order[:invoice_debit][:date])).nil?)

              next if (order[:invoice_debit].blank? && FinancialYear.on(Date.parse(order[:date])).nil?)

              @last_sale_number = order[:name]
              next if find_and_update_existant_sale(order).present?

              if order[:order_lines_not_deleted].present? && order[:state] != 'cancelled'
                entity = find_or_create_entity(@vendor, order[:customer])
                create_sale(order, entity)
              end
            end

            break if data_orders.blank? || @page == 50
          end
          { created: @count_created, updated: @count_updated, last_sale_number_created: @last_sale_number }
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

              debit_nature = order[:invoice_debit] || order[:receipt_debit]
              sale.reference_number = debit_nature[:name] if baqio_sale_state == :invoice && debit_nature.present?
              sale.save!
              @count_updated += 1
              @last_sale_number = sale.reference_number
              update_sale_state(sale, order)
              attach_pdf_to_sale(sale, debit_nature) if baqio_sale_state == :invoice
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
            debit_nature = order[:invoice_debit] || order[:receipt_debit]
            sale.reference_number =  debit_nature[:name] if (BQ_STATE[order[:state].to_sym] == :invoice && debit_nature.present?)
            sale.created_at = order[:created_at].to_time
            create_sale_items(sale, order)
            unless sale.save!
              raise StandardError.new("Error on creating sale #{order[:name]} : #{sale.errors.full_messages}")
            end

            @count_created += 1
            @last_sale_number = sale.reference_number

            update_sale_state(sale, order)
            attach_pdf_to_sale(sale, debit_nature)

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
            if order[:invoice_debit].present? && order[:invoice_debit][:date].present?
              order_date = Date.parse(order[:invoice_debit][:date]).to_time + 12.hours
            else
              order_date = Date.parse(order[:date]).to_time + 12.hours
            end
            baqio_sale_state = BQ_STATE[order[:state].to_sym]

            sale.correct if baqio_sale_state == :aborted
            sale.correct if baqio_sale_state == :estimate
            sale.propose if baqio_sale_state == :estimate || sale.items.present?
            sale.abort if baqio_sale_state == :aborted
            sale.confirm(order_date) if baqio_sale_state == :order
            sale.invoice(order_date) if baqio_sale_state == :invoice
          end

          def attach_pdf_to_sale(sale, debit)
            if debit.present? && find_doc_url(debit).present? && debit[:name].present?
              doc = Document.new(file: URI.parse(find_doc_url(debit).to_s).open, name: debit[:name],
  file_file_name: debit[:name] + '.pdf')
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
            # case of order come from point of sale
            if order_customer.nil?
              order_customer = create_pos_entity
            end
            entity = Integrations::Baqio::Handlers::Entities.new(vendor: vendor, order_customer: order_customer)
            entity.bulk_find_or_create
          end

          def find_doc_url(debit)
            if debit[:file_url].present?
              debit[:file_url]
            elsif debit[:file].present? && debit[:file][:url].present?
              debit[:file][:url]
            else
              nil
            end
          end

          # create an entity for order coming from POS without customer informations
          def create_pos_entity
            {
              id: 0,
              name: 'POS Client Baqio',
              billing_information: {
                first_name: nil,
                last_name: nil,
                company_name: nil,
                city: nil,
                zip: nil,
                mobile: nil,
                vat_number: nil,
                phone: nil,
                address1: nil,
                email: nil,
                website: nil,
                country_code: 'fr'
              }
            }
          end

      end
    end
  end
end
