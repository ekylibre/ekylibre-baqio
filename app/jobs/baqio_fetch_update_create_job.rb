class BaqioFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  def perform
    begin
      Baqio::BaqioIntegration.fetch_orders.execute do |c|
        c.success do |list|
          orders = []
          list.map do |order|
            # Create or Find existing Entity / customer at Samsys
            # order[:customer][:id]
            # order[:customer][:name]
            # order[:customer][:email]
            # order[:customer][:]
            entities = Entity.where("provider ->> 'id' = ?", order[:id].to_s)
            if entities.any?
              puts entities.first.inspect.yellow
              entity = entities.first
            else
              custom_name = if order[:customer][:billing_information][:last_name].nil? 
                              order[:customer][:billing_information][:company_name] 
                            else
                              order[:customer][:billing_information][:last_name]
                            end

              entity = Entity.create!(
                first_name: order[:customer][:billing_information][:first_name],
                last_name: custom_name,
                provider: { id: order[:id] }
              )
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
    end
  end

  private

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
  