module EkylibreBaqio
  class Engine < ::Rails::Engine
    initializer 'ekylibre_baqio.assets.precompile' do |app|
      app.config.assets.precompile += %w[baqio.js integrations/baqio.png]
    end

    initializer :ekylibre_baqio_i18n do |app|
      app.config.i18n.load_path += Dir[EkylibreBaqio::Engine.root.join('config', 'locales', '**', '*.yml')]
    end

    initializer :ekylibre_baqio_beehive do |app|
      app.config.x.beehive.cell_controller_types << :last_sales_baqio
    end

    initializer :ekylibre_baqio_beehive do |app|
      app.config.x.beehive.cell_controller_types << :last_sales_baqio
    end

    initializer :ekylibre_baqio_import_javascript do
      tmp_file = Rails.root.join('tmp', 'plugins', 'javascript-addons', 'plugins.js.coffee')
      tmp_file.open('a') do |f|
        import = '#= require baqio'
        f.puts(import) unless tmp_file.open('r').read.include?(import)
      end
    end

  end
end
