# frozen_string_literal: true

module Integrations
  module Baqio 
    module Handlers
      class IncomingPayments
        def initialize(vendor:, sale:, order:)
          @vendor = vendor
          @sale = sale 
          @order = order
        end

        def bulk_create_update_or_delete
          @order[:payment_links].each do |payment_link|
            create_update_or_delete_incoming_payment(@sale, payment_link)
          end
        end

        private 
        
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

      end
    end
  end
end