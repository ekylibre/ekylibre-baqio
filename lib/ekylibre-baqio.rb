require 'ekylibre-baqio/engine'

module EkylibreBaqio
  def self.root
    Pathname.new(File.dirname(__dir__))
  end
end
