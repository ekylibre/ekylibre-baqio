# frozen_string_literal: true

module Integrations
  module Baqio 
    module Handlers
      class SaleItems

        BAQIO_TAX_TYPE_TO_EKY = {
          "standard" => "normal_vat", "intermediate" => "intermediate_vat", 
          "reduced" => "reduced_vat", "exceptional" => "particular_vat"
        }

        def initialize(vendor:, sale: ,order:)
          @vendor = vendor
          @sale = sale
          @order = order
        end

        def bulk_create
          if @order[:order_lines_not_deleted].present?
            @order[:order_lines_not_deleted].each do |order_line_not_deleted|
              create_sale_items(@sale, @order, order_line_not_deleted)
            end
          end
        end

        def bulk_create_shipping_line_sale_item
          if @order[:shipping_line][:price_cents] > 0
            create_shipping_line_sale_item(@sale, @order[:shipping_line], @order)
          end
        end

        private 

        def create_sale_items(sale, order, order_line_not_deleted)
          eky_tax = find_baqio_tax_to_eky(order_line_not_deleted, order)
          variant = find_or_create_variant(order_line_not_deleted)
          reduction_percentage = order_line_not_deleted[:total_discount_cents] == 0 ? 0 : (order_line_not_deleted[:total_discount_cents].to_f /  order_line_not_deleted[:final_price_cents].to_f) * 100
      
          sale.items.build(
            sale_id: sale.id,
            variant_id: variant.id,
            label: "#{order_line_not_deleted[:name]} - #{order_line_not_deleted[:complement]} - #{order_line_not_deleted[:description]}",
            currency: order_line_not_deleted[:price_currency],
            quantity: order_line_not_deleted[:quantity].to_d,
            reduction_percentage: reduction_percentage,
            pretax_amount: (order_line_not_deleted[:final_price_cents] / 100.0).to_d,
            amount: (order_line_not_deleted[:final_price_with_tax_cents] / 100.0).to_d,
            compute_from: "pretax_amount",
            tax_id: eky_tax.id
          )
        end

        def create_shipping_line_sale_item(sale, shipping_line, order)
          shipping_line_tax_price_cents = shipping_line[:price_with_tax_cents] - shipping_line[:price_cents]
          # Find shipping_line tax_line throught order[:tax_line] with price_cents
          shipping_line_tax_line = order[:tax_lines].select {|t| t[:price_cents] == shipping_line_tax_price_cents }
      
          eky_tax = if shipping_line_tax_line.present?
                      find_baqio_country_tax(shipping_line_tax_line)
                      Tax.find_by(country: @country_tax_code, amount: @country_tax_percentage, nature: @country_tax_type)
                    else
                      Tax.find_by(nature: "null_vat")
                    end
          
          variant = ProductNatureVariant.import_from_nomenclature(:carriage)
      
          sale.items.build(
            sale_id: sale.id,
            variant_id: variant.id,
            label: "#{shipping_line[:name]}",
            currency: shipping_line[:price_currency],
            quantity: 1,
            unit_pretax_amount: (shipping_line[:price_cents] / 100.0).to_d,
            pretax_amount: (shipping_line[:price_cents] / 100.0).to_d,
            amount: (shipping_line[:price_with_tax_cents] / 100.0).to_d,
            compute_from: "amount",
            tax_id: eky_tax.id
          )
        end

        def find_baqio_tax_to_eky(order_line_not_deleted, order)
          if order_line_not_deleted[:tax_lines].present?
            find_baqio_country_tax(order_line_not_deleted[:tax_lines])
            return Tax.find_by(country: @country_tax_code, amount: @country_tax_percentage, nature: @country_tax_type)
      
          elsif order[:accounting_tax] == 'fr' && !order_line_not_deleted[:tax_lines].present? && order[:tax_lines].present?
            find_baqio_country_tax(order[:tax_lines])
            return Tax.find_by(country: @country_tax_code, amount: @country_tax_percentage, nature: @country_tax_type)
      
          elsif order[:accounting_tax] == 'fr' && !order_line_not_deleted[:tax_lines].present? && !order[:tax_lines].present?
            return Tax.find_by(nature: "null_vat")
      
          else
            return Tax.find_by(nature: 'eu_vat', amount: 0.0) if order[:accounting_tax] == 'eu'
            return Tax.find_by(nature: 'import_export_vat', amount: 0.0) if order[:accounting_tax] == 'world'
          end 
        end
      
        def find_baqio_country_tax(tax_line)
          country_tax_id = tax_line.first[:country_tax_id].to_i
          country_tax_baqio = Integrations::Baqio::Data::CountryTaxes.new(country_tax_id: country_tax_id).result.first

          @country_tax_code = country_tax_baqio[:code].downcase
          @country_tax_percentage = country_tax_baqio[:tax_percentage].to_f
          @country_tax_type = BAQIO_TAX_TYPE_TO_EKY[country_tax_baqio[:tax_type]]
        end

        def find_or_create_variant(order_line_not_deleted)
          variant = Integrations::Baqio::Handlers::ProductNatureVariants.new(vendor: @vendor, order_line_not_deleted: order_line_not_deleted)
          variant.bulk_find_or_create
        end

      end
    end
  end
end