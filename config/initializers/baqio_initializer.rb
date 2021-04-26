Baqio::BaqioIntegration.on_check_success do
  BaqioFetchUpdateCreateJob.perform_later
end

Baqio::BaqioIntegration.run every: :hour do
  if Integration.find_by(nature: "baqio").present?
    BaqioFetchUpdateCreateJob.perform_now
  end
end
  