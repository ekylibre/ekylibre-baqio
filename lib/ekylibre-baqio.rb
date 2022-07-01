require 'ekylibre-baqio/engine'

module EkylibreBaqio
  VENDOR = 'baqio'

  def self.root
    Pathname.new(File.dirname(__dir__))
  end
end
