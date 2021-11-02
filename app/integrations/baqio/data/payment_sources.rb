# frozen_string_literal: true

module Baqio
  module Data
    class PaymentSources
      def result
        @formated_data ||= call_api
      end

      def format_data(list)
        list.select{ |c| c[:displayed] == true }.map do |payment_source|
          payment_source.filter{ |k, _v| desired_fields.include?(k) }
        end
      end

      private

      def call_api
        ::Baqio::BaqioIntegration.fetch_payment_sources.execute do |c|
          c.success do |list|
            format_data(list)
          end
        end
      end

      def desired_fields
        %i[id name bank_information_id]
      end
    end
  end
end
