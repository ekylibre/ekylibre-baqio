class BaqioFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  def perform
    # Page need to be set-up to fetch orders from different Baqio pages
    @page = 0

    # Set page_with_ordres to ended the job if orders page is blank
    @page_with_orders = []

    begin
      Baqio::BaqioIntegration.fetch_orders(@page +=1).execute do |c|
        c.success do |list|
          orders = []
          @page_with_orders = list
          puts list.inspect.green
          list.map do |order|
            # Create or Find existing Entity / customer at Samsys
            # order[:customer][:id]
            # order[:customer][:name]
            # order[:customer][:email]
            # order[:customer][:]
            entities = Entity.where("provider ->> 'id' = ?", order[:customer][:id].to_s)
            if entities.any?
              entity = entities.first
            else
              custom_name = if order[:customer][:billing_information][:last_name].nil? 
                              order[:customer][:billing_information][:company_name] 
                            else
                              order[:customer][:billing_information][:last_name]
                            end
              # TODO check and add custom nature (ex: Customer "Particulier" at Baqio become "Contact" nature at Ekylibre)
              # Need API update from Baqio, method customer/id doesn't work
              entity = Entity.create!(
                first_name: order[:customer][:billing_information][:first_name],
                last_name: custom_name,
                provider: {vendor: "Baqio", name: "Baqio_order_customer", id: order[:customer][:id]}
              )

              zip_city = build_address_cz(
                order[:customer][:billing_information][:city],
                order[:customer][:billing_information][:zip]
              )

              entity_addresses = Array.new([
                { mobile: order[:customer][:billing_information][:mobile] },
                { zip_city: zip_city , mail: order[:customer][:billing_information][:address1]},
                { email: order[:customer][:billing_information][:email] },
                { website: order[:customer][:billing_information][:website] }
              ])

              # Create EntityAddress for every valid entity_addresses got from Baqio
              entity_addresses.each do |entity_address|
                unless entity_address.values.first.blank?
                  if entity_address.keys.last == :mail 
                    EntityAddress.create!(
                      entity_id: entity.id,
                      canal: "mail",
                      mail_line_4: entity_address[:mail],
                      mail_line_6: entity_address[:zip_city]
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

            # Create or Find Sale
          end
          puts orders.first.inspect.red

        end
      end
    
    rescue StandardError => error
      Rails.logger.error $!
      Rails.logger.error $!.backtrace.join("\n")
      ExceptionNotifier.notify_exception($!, data: { message: error })
    end while @page_with_orders.blank? == false || @page == 50
  end

  private


  def build_address_cz(city, zip)
    return nil if city.blank? && zip.blank?
    build_c = city.nil? ? "" : city + ", "
    build_z = zip.nil? ? "" : zip

    "#{build_c}#{build_z}"
  end

  def error_notification_params(error)
    {
      message: 'error_during_baqio_api_call',
      level: :error,
      target_type: '',
      target_url: '',
      interpolations: {
        error_message: error
      }
    }
  end
end
  