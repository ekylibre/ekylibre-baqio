# frozen_string_literal: true

class BaqioFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  VENDOR = 'baqio'

  def perform(user_id: nil)
    Preference.set!(:baqio_fetch_job_running, true, :boolean)
    user = User.find_by_id(user_id)
    unless FinancialYear.opened.current
      @error = :no_financial_year_opened.tl
      if user
        user.notifications.create!(error_during_baqio_api_call)
      else
        ExceptionNotifier.notify_exception($ERROR_INFO, data: { message: @error })
      end
    end

    begin
      # Create ProductNatureCategory and ProductNature from Baqio product_families
      pnc_handler = Integrations::Baqio::Handlers::ProductNatureCategories.new(vendor: VENDOR)
      pnc_handler.bulk_find_or_create

      # call create or update cashes from baqio api
      cash_handler = Integrations::Baqio::Handlers::Cashes.new(vendor: VENDOR)
      cash_handler.bulk_find_or_create

      # create or update incoming_payment_mode from baqio api
      incoming_payment_mode_handler = Integrations::Baqio::Handlers::IncomingPaymentModes.new(vendor: VENDOR)
      incoming_payment_mode_handler.bulk_find_or_create

      # create or update product_nature_variant from baqio api
      product_nature_variant = Integrations::Baqio::Handlers::ProductNatureVariants.new(vendor: VENDOR)
      product_nature_variant.bulk_find_or_create

      # create or update sales from baqio api
      sales = Integrations::Baqio::Handlers::Sales.new(vendor: VENDOR, user_id: user_id)
      result = sales.bulk_find_or_create
    rescue StandardError => error
      Rails.logger.error $ERROR_INFO
      Rails.logger.error $ERROR_INFO.backtrace.join("\n")
      @error = error
      ExceptionNotifier.notify_exception($ERROR_INFO, data: { message: error })
    end
    if user
      ActionCable.server.broadcast("main_#{user.email}", event: 'update_job_over')
      notif_params =  if @error.present?
                        error_during_baqio_api_call
                      else
                        correct_baqio_fetch_params(result)
                      end
      locale = user.language.present? ? user.language.to_sym : :eng
      I18n.with_locale(locale) do
        user.notifications.create!(notif_params)
      end
    end
    Preference.set!(:baqio_fetch_job_running, false, :boolean)
  end

  private

    def error_during_baqio_api_call
      {
        message: :error_during_baqio_api_call.tl,
        level: :error,
        interpolations: {
          error: @error
        }
      }
    end

    def correct_baqio_fetch_params(result)
      {
        message: :success_sync_baqio.tl,
        level: :success,
        target_url: '/backend/sales',
        interpolations: {
          created: result[:created].to_s,
          updated: result[:updated].to_s,
          last_sale_number_created: result[:last_sale_number_created].to_s
        }
      }
    end
end
