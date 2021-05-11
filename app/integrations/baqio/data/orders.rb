# frozen_string_literal: true

module Integrations
  module Baqio 
    module Data 
      class Orders
        def initialize(page_number)
          @formated_data = nil
          @page_number = page_number
          @max_date = FinancialYear.where(state: "opened").map{ |date| date.stopped_on.to_time }
          @min_date = FinancialYear.where(state: "opened").map{ |date| date.started_on.to_time }
        end
        
        def result
          @formated_data ||= call_api
        end

        def format_data(list)
          list.map do |order|
            data_order = order.filter { |k, v| simple_desired_fields.include?(k) }
            data_order[:customer] = format_order_customer(order[:customer])
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
          [:id, :name, :state, :date, :updated_at, :created_at, :shipping_line, :order_lines_not_deleted, :invoice_debit, :payment_links, :tax_lines, :accounting_tax ] 
        end

        def format_order_customer(order_customer)
          desired_fields = [:id, :name]
          data = order_customer.filter { |k, v| desired_fields.include?(k) }
          data[:billing_information] = format_order_customer_billing_information(order_customer[:billing_information])
          data
        end

        def format_order_customer_billing_information(billing_information)
          desired_fields = [:first_name, :last_name, :company_name, :city, :zip, :mobile, :address1, :email, :website]
          billing_information.filter { |k, v| desired_fields.include?(k) }
        end


        def format_order_lines_not_deleted(order_lines_not_deleted)
          desired_fields = [:id, :account_id, :name]
          order_lines_not_deleted.filter { |k, v| desired_fields.include?(k) }
        end
      end
    end
  end
end