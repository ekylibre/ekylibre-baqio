# frozen_string_literal: true

module Integrations
  module Baqio 
    module Data 
      class BankInformations
        def initialize
          @formated_data = nil
        end
        
        def result
          @formated_data ||= call_api
        end

        def format_data(list)
          list.map do |bank_information|
            bank_information.filter{ |k, v| desired_fields.include?(k) }
          end
        end

        private 

        def call_api
          ::Baqio::BaqioIntegration.fetch_bank_informations.execute do |c|
            c.success do |list|
              format_data(list)
            end
          end
        end

        def desired_fields
          [:id, :iban, :domiciliation, :bic, :owner, :primary]
        end

      end
    end
  end
end