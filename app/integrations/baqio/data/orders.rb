# frozen_string_literal: true

module Integrations
  module Baqio
    module Data
      class Orders
        def initialize(page_number)
          @page_number = page_number
          @max_date = FinancialYear.where(state: 'opened').map{ |date| date.stopped_on.to_time }
          @min_date = FinancialYear.where(state: 'opened').map{ |date| date.started_on.to_time }
        end

        def result
          @formated_data ||= call_api
        end

        def format_data(list)
          list.map do |order|
            data_order = order.filter { |k, _v| simple_desired_fields.include?(k) }
            data_order[:customer] = format_order_customer(order[:customer])
            data_order[:order_lines_not_deleted] = format_order_lines_not_deleted(order[:order_lines_not_deleted])
            data_order[:shipping_line] = format_order_shipping_line(order[:shipping_line])
            data_order[:payment_links] = format_order_payment_sources(order[:payment_links])
            data_order
          end
        end

        private

          def call_api
            ::Baqio::BaqioIntegration.fetch_orders(@page_number).execute do |c|
              c.success do |list|
                format_data(list.select { |order| @max_date.max > order[:date].to_time && order[:date].to_time > @min_date.min } )
              end
            end
          end

          def simple_desired_fields
            %i[id name state date updated_at created_at total_price_cents invoice_debit invoice_credit tax_lines accounting_tax]
          end

          def format_order_customer(order_customer)
            desired_fields = %i[id name]
            data = order_customer.filter { |k, _v| desired_fields.include?(k) }
            data[:billing_information] = format_order_customer_billing_information(order_customer[:billing_information])
            data
          end

          def format_order_customer_billing_information(billing_information)
            desired_fields = %i[first_name last_name company_name city zip mobile address1 email website country_code]
            billing_information.filter { |k, _v| desired_fields.include?(k) }
          end

          def format_order_lines_not_deleted(order_lines_not_deleted)
            order_lines_not_deleted.map do |order_line_not_deleted|
              desired_fields = %i[id name complement description total_discount_cents final_price_cents price_currency
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

          def format_order_payment_sources_payment(order_payment_sources_payment)
            desired_fields = %i[id payment_source_id amount_cents date amount_currency deleted_at]
            order_payment_sources_payment.filter { |k, _v| desired_fields.include?(k) }
          end
      end
    end
  end
end
