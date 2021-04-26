module EkylibreBaqio
  class Engine < ::Rails::Engine
    initializer 'ekylibre_baqio.assets.precompile' do |app|
      app.config.assets.precompile += %w(integrations/baqio.png)
    end

    initializer :ekylibre_baqio_i18n do |app|
      app.config.i18n.load_path += Dir[EkylibreBaqio::Engine.root.join('config', 'locales', '**', '*.yml')]
    end

    initializer :ekylibre_baqio_beehive do |app|
      app.config.x.beehive.cell_controller_types << :last_sales_baqio
    end
  end
end
