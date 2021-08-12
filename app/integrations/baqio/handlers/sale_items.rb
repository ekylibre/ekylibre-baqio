# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class SaleItems

        BAQIO_TAX_TYPE_TO_EKY = {
          standard: 'normal_vat',
          intermediate: 'intermediate_vat',
          reduced: 'reduced_vat',
          exceptional: 'particular_vat'
        }.freeze

        EU_CT_CODE = %w[BE DE DK].freeze

        def initialize(vendor:, sale:, order:)
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
            pretax_amount = (order_line_not_deleted[:final_price_cents] / 100.0).to_f
            reduction_percentage = compute_reduction_percentage(order_line_not_deleted)

            sale.items.build(
              sale_id: sale.id,
              variant_id: variant.id,
              label: "#{order_line_not_deleted[:name]} - #{order_line_not_deleted[:complement]} - #{order_line_not_deleted[:description]}",
              currency: order_line_not_deleted[:price_currency],
              quantity: order_line_not_deleted[:quantity].to_d,
              reduction_percentage: reduction_percentage,
              unit_pretax_amount: (pretax_amount / order_line_not_deleted[:quantity].to_f).round(2),
              pretax_amount: pretax_amount,
              amount: (order_line_not_deleted[:final_price_with_tax_cents] / 100.0).to_d,
              compute_from: 'pretax_amount',
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
                        Tax.find_by(nature: 'null_vat')
                      end

            variant = ProductNatureVariant.import_from_lexicon(:transportation)

            sale.items.build(
              sale_id: sale.id,
              variant_id: variant.id,
              label: (shipping_line[:name]).to_s,
              currency: shipping_line[:price_currency],
              quantity: 1,
              unit_pretax_amount: (shipping_line[:price_cents] / 100.0).to_d,
              pretax_amount: (shipping_line[:price_cents] / 100.0).to_d,
              amount: (shipping_line[:price_with_tax_cents] / 100.0).to_d,
              compute_from: 'amount',
              tax_id: eky_tax.id
            )
          end

          def compute_reduction_percentage(order_line_not_deleted)
            compute_reduction = (order_line_not_deleted[:total_discount_cents].to_f / order_line_not_deleted[:final_price_cents].to_f) * 100

            if order_line_not_deleted[:final_price_cents].zero? && !order_line_not_deleted[:total_discount_cents].zero?
              100
            elsif order_line_not_deleted[:total_discount_cents] == 0
              0
            else
              compute_reduction
            end
          end

          def find_baqio_tax_to_eky(order_line_not_deleted, order)
            if order_line_not_deleted[:tax_lines].present?
              find_or_create_baqio_country_tax(order_line_not_deleted[:tax_lines])

            elsif order[:accounting_tax] == 'fr' && order[:tax_lines].present?
              find_or_create_baqio_country_tax(order[:tax_lines])

            elsif order[:accounting_tax] == 'fr' && !order[:tax_lines].present?
              Tax.find_by(nature: 'null_vat')

            elsif order[:accounting_tax] == 'fr_susp' && !order[:tax_lines].present?
              Tax.find_by(nature: 'null_vat')

            elsif order[:accounting_tax] == 'GB' && !order[:tax_lines].present?
              Tax.find_by(nature: 'import_export_vat', amount: 0.0)

            elsif EU_CT_CODE.include?(order[:accounting_tax]) && !order[:tax_lines].present?
              Tax.find_by(nature: 'eu_vat', amount: 0.0)

            elsif order[:accounting_tax] == 'eu'
              Tax.find_by(nature: 'eu_vat', amount: 0.0)
            
            elsif order[:accounting_tax] == 'world'
              Tax.find_by(nature: 'import_export_vat', amount: 0.0)
            end
          end

          def find_or_create_baqio_country_tax(tax_line)
            country_tax_id = tax_line.first[:country_tax_id].to_i
            country_tax_baqio = Integrations::Baqio::Data::CountryTaxes.new(country_tax_id: country_tax_id).result.first

            country_tax_code = country_tax_baqio[:code].downcase
            country_tax_percentage = country_tax_baqio[:tax_percentage].to_f
            country_tax_type = BAQIO_TAX_TYPE_TO_EKY[country_tax_baqio[:tax_type].to_sym]

            baqio_tax = Tax.find_by(country: country_tax_code, amount: country_tax_percentage, nature: country_tax_type)

            if baqio_tax.present?
              baqio_tax
            else
              # Import all tax from onoma with country_tax_code (eg: "fr", "dk")
              Tax.import_all_from_nomenclature(country: country_tax_code)
              Tax.find_by(country: country_tax_code, amount: country_tax_percentage, nature: country_tax_type)
            end
          end

          def find_or_create_variant(order_line_not_deleted)
            variant = Integrations::Baqio::Handlers::ProductNatureVariants.new(vendor: @vendor,
  order_line_not_deleted: order_line_not_deleted)
            variant.bulk_find_or_create
          end

      end
    end
  end
end
