module Backend
  class BaqioSynchroController < Backend::BaseController

    def synchronize
      BaqioFetchUpdateCreateJob.perform_later(user_id: current_user)
      redirect_to backend_sales_path
    end
  end
end
