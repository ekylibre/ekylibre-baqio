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

        EU_CT_CODE = %w[BE DE DK IT].freeze

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
            variant = ProductNatureVariant.of_provider_vendor(@vendor)
                                          .of_provider_data(:id, order_line_not_deleted[:product_variant_id].to_s).first
            pretax_amount = (order_line_not_deleted[:final_price_cents] / 100.0).to_f
            reduction_percentage = compute_reduction_percentage(order_line_not_deleted)

            # If conditionning is created in product nature variant
            product_size_id = order_line_not_deleted[:product_variant][:product_size_id]
            conditioning_unit = if product_size_id.present?
                                  Conditioning.of_provider_vendor(@vendor).of_provider_data(:id, product_size_id.to_s).first
                                else
                                  Unit.import_from_lexicon('unity')
                                end

            sale.items.build(
              sale_id: sale.id,
              variant_id: variant.id,
              label: "#{order_line_not_deleted[:name]} - #{order_line_not_deleted[:complement]}",
              currency: order_line_not_deleted[:price_currency],
              quantity: order_line_not_deleted[:quantity].to_d,
              reduction_percentage: reduction_percentage,
              unit_pretax_amount: (order_line_not_deleted[:price_cents].to_f / 100),
              pretax_amount: pretax_amount,
              amount: (order_line_not_deleted[:final_price_with_tax_cents] / 100.0).to_d,
              compute_from: 'pretax_amount',
              tax_id: eky_tax.id,
              conditioning_unit_id: conditioning_unit.id,
              conditioning_quantity: order_line_not_deleted[:quantity].to_d
            )

          end

          def create_shipping_line_sale_item(sale, shipping_line, order)
            # Find shipping_line tax throught order[:tax_lines]
            eky_tax = if order[:tax_lines].present?
                        find_or_create_baqio_country_tax(order[:tax_lines])
                      else
                        Tax.find_by(nature: 'null_vat')
                      end

            variant = ProductNatureVariant.import_from_lexicon(:transportation)
            conditioning_unit = Unit.import_from_lexicon('unity')

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
              tax_id: eky_tax.id,
              conditioning_unit_id: conditioning_unit.id,
              conditioning_quantity: 1
            )

          end

          def compute_reduction_percentage(order_line_not_deleted)
            if order_line_not_deleted[:final_price_cents].zero? && !order_line_not_deleted[:total_discount_cents].zero?
              100
            elsif order_line_not_deleted[:total_discount_cents] == 0
              0
            else
              total_price_before_reduction = order_line_not_deleted[:price_cents] * order_line_not_deleted[:quantity].to_f
              compute_reduction = 100 - ((order_line_not_deleted[:final_price_cents].to_f / total_price_before_reduction.round(2)) * 100)
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

          def find_or_create_baqio_country_tax(tax_line, order)
            country_tax_id = tax_line.first[:country_tax_id].to_i
            country_tax_baqio = Integrations::Baqio::Data::CountryTaxes.new(country_tax_id: country_tax_id).result.first

            country_tax_code = country_tax_baqio[:code].downcase
            country_tax_percentage = country_tax_baqio[:tax_percentage].to_f
            country_tax_type = BAQIO_TAX_TYPE_TO_EKY[country_tax_baqio[:tax_type].to_sym]
            baqio_tax = Tax.find_by(country: country_tax_code, amount: country_tax_percentage, nature: country_tax_type)
            item = Onoma::Tax.find_by(country: country_tax_code.to_sym, amount: country_tax_percentage, nature: country_tax_type.to_sym) if country_tax_code.present? && country_tax_type.present?
            if baqio_tax.present?
              baqio_tax
            elsif item.present? && EU_CT_CODE.include?(order[:accounting_tax])
              # Import tax from onoma with country_tax_code (eg: "de" ,"dk") and with option from export_private_sale
              Tax.import_from_nomenclature(item.name)
            elsif item.present?
              # Import tax from onoma with country_tax_code (:fr)
              Tax.import_from_nomenclature(item.name)
            end
          end

      end
    end
  end
end
