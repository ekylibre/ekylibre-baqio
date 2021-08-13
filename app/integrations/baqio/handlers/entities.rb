# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class Entities
        def initialize(vendor:, order_customer:)
          @vendor = vendor
          @order_customer = order_customer
        end

        def bulk_find_or_create
          entity = Entity.of_provider_vendor(@vendor).of_provider_data(:id, @order_customer[:id].to_s).first

          if entity.present?
            entity
          else
            create_entity(@order_customer)
          end
        end

        private

          def create_entity(order_customer)
            # TO REMOVE later / Create only 2 orders for testing
            billing_information = order_customer[:billing_information]

            custom_name = if billing_information[:last_name].nil? && billing_information[:company_name].present?
                            billing_information[:company_name]
                          else
                            order_customer[:name]
                          end
            # TODO: check and add custom nature (ex: Customer "Particulier" at Baqio become "Contact" nature at Ekylibre)
            # Need API update from Baqio, method customer/id doesn't work
            entity = Entity.create!(
              first_name: billing_information[:first_name],
              last_name: custom_name,
              client: true,
              country: billing_information[:country_code].lower,
              provider: {
                    vendor: @vendor,
                    name: 'Baqio_order_customer',
                    data: { id: order_customer[:id].to_s }
                    }
            )

            create_entity_addresses(order_customer, entity)

            entity
          end

          def create_entity_addresses(order_customer, entity)
            zip_city = build_address_cz(
              order_customer[:billing_information][:city],
              order_customer[:billing_information][:zip]
            )

            country_code =  if order_customer[:billing_information][:country_code].present?
                              order_customer[:billing_information][:country_code].lower
                            else
                              'fr'
                            end

            entity_addresses = Array.new([
              { mobile: order_customer[:billing_information][:mobile] },
              { zip_city: zip_city, country_code: country_code, mail: order_customer[:billing_information][:address1] },
              { email: order_customer[:billing_information][:email] },
              { website: order_customer[:billing_information][:website] }
            ])

            # Create EntityAddress for every valid entity_addresses got from Baqio
            entity_addresses.each do |entity_address|
              unless entity_address.values.first.blank?
                if entity_address.keys.last == :mail
                  EntityAddress.create!(
                    entity_id: entity.id,
                    canal: 'mail',
                    mail_line_4: entity_address[:mail],
                    mail_line_6: entity_address[:zip_city],
                    mail_country:  entity_address[:country_code]
                  )
                else
                  EntityAddress.create!(
                    entity_id: entity.id,
                    canal: entity_address.keys.first.to_s,
                    coordinate: entity_address.values.first
                  )
                end
              end
            end
          end

          def build_address_cz(city, zip)
            return nil if city.blank? && zip.blank?

            build_c = city.nil? ? '' : city + ', '
            build_z = zip.nil? ? '' : zip

            "#{build_c}#{build_z}"
          end

      end
    end
  end
end
