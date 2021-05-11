# frozen_string_literal: true

class BaqioFetchUpdateCreateJob < ActiveJob::Base
  queue_as :default
  include Rails.application.routes.url_helpers

  VENDOR = 'baqio'

  CATEGORY = "wine"

  BANK_ACCOUNT_PREFIX_NUMBER = "512201"

  BAQIO_CASH_ACCOUNT_NUMBER = 531201

  def perform
    begin
      # Create ProductNatureCategory and ProductNature from Baqio product_families
      pnc_handler = Integrations::Baqio::Handlers::ProductNatureCategories.new(vendor: VENDOR, category: CATEGORY)
      pnc_handler.bulk_find_or_create

      # TODO call create or update cashes from baqio api
      cash_handler = Integrations::Baqio::Handlers::Cashes.new(vendor: VENDOR, bank_account_prefix_number: BANK_ACCOUNT_PREFIX_NUMBER)
      cash_handler.bulk_find_or_create

      # TODO create or update incoming_payment_mode from baqio api
      incoming_payment_mode_handler = Integrations::Baqio::Handlers::IncomingPaymentModes.new(vendor: VENDOR)
      incoming_payment_mode_handler.bulk_find_or_create

      sales = Integrations::Baqio::Handlers::Sales.new(vendor: VENDOR)
      sales.bulk_find_or_create

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
