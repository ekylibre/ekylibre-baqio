module Backend
  class BaqioSynchroController < Backend::BaseController

    def synchronize
      puts params.inspect.yellow
      BaqioFetchUpdateCreateJob.perform_later(from_to: params[:from_to], up_to: params[:up_to], user_id: current_user.id)
      redirect_to backend_sales_path
    end
  end
end
