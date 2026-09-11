# Rails 7 n'installe le chargeur principal que dans le *finisher*, après les
# initialiseurs : `Baqio::BaqioIntegration` n'y est pas encore autochargeable.
# `to_prepare` s'exécute juste après le démarrage, et à chaque rechargement.
Rails.application.config.to_prepare do
  Baqio::BaqioIntegration.on_check_success do
    BaqioFetchUpdateCreateJob.perform_later
  end

  Baqio::BaqioIntegration.run every: :day do
    if Integration.find_by(nature: 'baqio').present? && !FinancialYearExchange.opened.present?
      BaqioFetchUpdateCreateJob.perform_now
    end
  end
end
