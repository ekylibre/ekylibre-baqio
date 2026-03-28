# frozen_string_literal: true

module Integrations
  module Baqio
    module Data
      class Orders
        def initialize(page_number, user_id, min_date = nil, max_date = nil)
          @page_number = page_number
          @user_id = user_id
          @max_date = max_date || Time.now
          @min_date = min_date || FinancialYear.opened.current.started_on.to_time
        end

        def result
          @formated_data ||= call_api
        end

        def format_data(list)
          list.map do |order|

            # next if no customer or no ticket for pos
            if (order[:customer].nil? && order[:receipt_debit].nil?)
              # notification_order_without_customer(order[:id])
              next
            end

            # next if no date in financial year for order
            if order[:invoice_debit].present? && FinancialYear.opened.on(Date.parse(order[:invoice_debit][:date].to_s)).nil?
              notification_order_date_out_range(order[:id], order[:invoice_debit][:date])
              next
            end

            # next if no date in financial year for payment_link
            if order[:payment_links].present?
              order[:payment_links].each do |payment_link|
                baqio_payment_date = Date.parse(payment_link[:payment][:date].to_s)
                if FinancialYear.opened.on(baqio_payment_date).nil?
                  notification_order_date_out_range(order[:id], baqio_payment_date)
                  next
                end
              end
            end

            data_order = order.filter { |k, _v| simple_desired_fields.include?(k) }
            data_order[:receipt_debit] = format_order_receipt_debit(order[:receipt_debit]) if order[:receipt_debit].present?
            data_order[:customer] = format_order_customer(order[:customer]) if order[:customer].present?
            data_order[:order_lines_not_deleted] = format_order_lines_not_deleted(order[:order_lines_not_deleted])
            data_order[:shipping_line] = format_order_shipping_line(order[:shipping_line])
            data_order[:payment_links] = format_order_payment_sources(order[:payment_links])
            data_order[:operations] = format_order_operations(order[:operations]) if order[:operations].present?
            data_order
          end
        end

        private

          def call_api
            ::Baqio::BaqioIntegration.fetch_orders(@page_number, @min_date.to_date.to_s, @max_date.to_date.to_s).execute do |c|
              c.success do |list|
                format_data(list)
              end
            end
          end

          def simple_desired_fields
            %i[id name state date updated_at created_at total_price_cents invoice_debit receipt_debit invoice_credit tax_lines accounting_tax operations]
          end

          def format_order_customer(order_customer)
            desired_fields = %i[id name]
            data = order_customer.filter { |k, _v| desired_fields.include?(k) }
            data[:billing_information] = format_order_customer_billing_information(order_customer[:billing_information])
            data
          end

          def format_order_customer_billing_information(billing_information)
            desired_fields = %i[first_name last_name company_name city zip mobile vat_number phone address1 email website country_code]
            billing_information.filter { |k, _v| desired_fields.include?(k) }
          end

          def format_order_lines_not_deleted(order_lines_not_deleted)
            order_lines_not_deleted.map do |order_line_not_deleted|
              desired_fields = %i[id name complement description price_cents total_discount_cents final_price_cents price_currency
                                  quantity final_price_with_tax_cents tax_lines product_variant_id product_variant]
              data = order_line_not_deleted.filter { |k, _v| desired_fields.include?(k) }
              data[:product_variant] = format_order_product_variant(order_line_not_deleted[:product_variant])
              data
            end
          end

          def format_order_product_variant(order_product_variant)
            desired_fields = %i[product_size_id]
            order_product_variant.filter { |k, _v| desired_fields.include?(k) }
          end

          def format_order_shipping_line(order_shipping_line)
            desired_fields = %i[id name price_currency price_with_tax_cents price_cents price_with_tax_cents]
            order_shipping_line.filter { |k, _v| desired_fields.include?(k) }
          end

          def format_order_payment_sources(order_payment_sources)
            order_payment_sources.map do |order_payment_source|
              desired_fields = [:id]
              data = order_payment_source.filter { |k, _v| desired_fields.include?(k) }
              data[:payment] = format_order_payment_sources_payment(order_payment_source[:payment])
              data
            end
          end

          # wait for add fees_cents in API
          def format_order_payment_sources_payment(order_payment_sources_payment)
            desired_fields = %i[id payment_source_id amount_cents date amount_currency deleted_at]
            order_payment_sources_payment.filter { |k, _v| desired_fields.include?(k) }
          end

          def format_order_receipt_debit(order_receipt_debit)
            desired_fields = %i[id number name status file]
            order_receipt_debit.filter { |k, _v| desired_fields.include?(k) }
          end

          # kind [discount_for_early_payment, management_loss, exchange_loss, extraordinary_charge, bad_debt]
          # status [charge, product]
          # accounting_tax [fr]
          # amount_cents is HT
          def format_order_operations(operations)
            desired_fields = %i[id accounting_tax account_id date status kind amount_cents]
            operations.filter { |k, _v| desired_fields.include?(k) }
          end

          def notification_order_without_customer(order_id)
            notif_params = error_baqio_order_without_customer(order_id)
            if (user = User.find_by_id(@user_id))
              locale = user.language.present? ? user.language.to_sym : :eng
              I18n.with_locale(locale) do
                user.notifications.create!(notif_params)
              end
            end
          end

          def error_baqio_order_without_customer(order_id)
            {
              message: :failed_sync_order_without_customer.tl + " (id: #{order_id})",
              level: :error,
              interpolations: {}
            }
          end

          def notification_order_date_out_range(order_id, order_date)
            notif_params = error_baqio_order_date_out_range(order_id, order_date)
            if (user = User.find_by_id(@user_id))
              locale = user.language.present? ? user.language.to_sym : :eng
              I18n.with_locale(locale) do
                user.notifications.create!(notif_params)
              end
            end
          end

          def error_baqio_order_date_out_range(order_id, order_date)
            {
              message: :failed_sync_order_date_out_range.tl + " (ID: #{order_id}, Date: #{order_date})",
              level: :error,
              interpolations: {}
            }
          end
      end
    end
  end
end
