# frozen_string_literal: true

class BaqioFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  VENDOR = 'baqio'

  def perform(user_id: nil)
    Preference.set!(:baqio_fetch_job_running, true, :boolean)
    begin
      # Create ProductNatureCategory and ProductNature from Baqio product_families
      pnc_handler = Baqio::Handlers::ProductNatureCategories.new(vendor: VENDOR)
      pnc_handler.bulk_find_or_create

      # TODO: call create or update cashes from baqio api
      cash_handler = Baqio::Handlers::Cashes.new(vendor: VENDOR)
      cash_handler.bulk_find_or_create

      # TODO: create or update incoming_payment_mode from baqio api
      incoming_payment_mode_handler = Baqio::Handlers::IncomingPaymentModes.new(vendor: VENDOR)
      incoming_payment_mode_handler.bulk_find_or_create

      sales = Baqio::Handlers::Sales.new(vendor: VENDOR)
      sales.bulk_find_or_create
    rescue StandardError => error
      Rails.logger.error $ERROR_INFO
      Rails.logger.error $ERROR_INFO.backtrace.join("\n")
      @error = error
      ExceptionNotifier.notify_exception($ERROR_INFO, data: { message: error })
    end
    if (user = User.find_by_id(user_id))
      ActionCable.server.broadcast("main_#{user.email}", event: 'update_job_over')
      notif_params =  if @error.nil?
                        correct_baqio_fetch_params
                      else
                        errors_baqio_fetch_params
                      end
      locale = user.language.present? ? user.language.to_sym : :eng
      I18n.with_locale(locale) do
        user.notifications.create!(notif_params)
      end
    end
    Preference.set!(:baqio_fetch_job_running, false, :boolean)
  end

  private

    def errors_baqio_fetch_params
      {
        message: :failed_baqio_fetch_params.tl,
        level: :error,
        interpolations: {}
      }
    end

    def correct_baqio_fetch_params
      {
        message: :correct_baqio_fetch_params.tl,
        level: :success,
        target_url: '/backend/sales',
        interpolations: {}
      }
    end
end
