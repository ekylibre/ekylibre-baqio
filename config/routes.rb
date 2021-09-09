Rails.application.routes.draw do
  concern :list do
    get :list, on: :collection
  end

  namespace :backend do
    namespace :cells do
      resource :last_sales_baqio_cell, only: :show, concerns: :list
    end
    get :baqio_synchro, to: 'baqio_synchro#synchronize'
  end
end
