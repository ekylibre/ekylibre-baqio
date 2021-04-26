module Backend
  module Cells
    class LastSalesBaqioCellsController < Backend::Cells::BaseController

      list(model: :sales, conditions: ("provider ->> 'vendor' = 'baqio'"), order: 'created_at DESC', per_page: 5) do |t|
        t.column :number, url: { controller: '/backend/sales' }
        t.column :created_at
        t.status
        t.column :state_label
        t.column :amount, currency: true
      end

      def show; end
    end
  end
end