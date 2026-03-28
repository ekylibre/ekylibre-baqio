# frozen_string_literal: true

module Integrations
  module Baqio
    module Handlers
      class SaleItems
        def initialize(vendor:, sale:, order:)
          @vendor = vendor
          @sale = sale
          @order = order
        end

        def bulk_create
          if @order[:order_lines_not_deleted].present?
            @order[:order_lines_not_deleted].each do |order_line_not_deleted|
              next if order_line_not_deleted[:quantity].to_d.zero? && order_line_not_deleted[:price_cents].to_d.zero?

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

            if variant.blank?
              pnv_service = Integrations::Baqio::Handlers::ProductNatureVariants.new(vendor: @vendor)
              variant = pnv_service.find_or_create(order_line_not_deleted[:product_variant_id])
              # raise StandardError.new("Missing variant creation for baqio variant id : #{order_line_not_deleted[:product_variant_id].to_s}")
            end

            unless eky_tax.present?
              raise StandardError.new("Missing tax creation for baqio tax : #{order_line_not_deleted[:tax_lines].to_s}")
            end

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
              unit_pretax_amount: (order_line_not_deleted[:price_cents] / 100.0).to_d,
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
                        find_or_create_baqio_country_tax(order[:tax_lines], order)
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
              total_price_before_reduction = order_line_not_deleted[:price_cents].to_f * order_line_not_deleted[:quantity].to_f
              compute_reduction = 100 - ((order_line_not_deleted[:final_price_cents].to_f / total_price_before_reduction.round(2)) * 100)
            end
          end

          def find_baqio_tax_to_eky(order_line_not_deleted, order)
            if order_line_not_deleted[:tax_lines].present?
              find_or_create_baqio_country_tax(order_line_not_deleted[:tax_lines], order)

            elsif order[:accounting_tax] == 'fr' && order[:tax_lines].present?
              find_or_create_baqio_country_tax(order[:tax_lines], order)

            elsif order[:accounting_tax] == 'fr' && !order[:tax_lines].present?
              Tax.find_by(nature: 'null_vat')

            elsif order[:accounting_tax] == 'fr_susp' && !order[:tax_lines].present?
              Tax.find_by(nature: 'null_vat')

            elsif order[:accounting_tax] == 'GB' && !order[:tax_lines].present?
              Tax.find_by(nature: 'import_export_vat', amount: 0.0)

            elsif Integrations::Baqio::Handlers::CountryTaxes::EU_CT_CODE.include?(order[:accounting_tax]) && !order[:tax_lines].present?
              Tax.find_by(nature: 'eu_vat', amount: 0.0)

            elsif order[:accounting_tax] == 'eu'
              Tax.find_by(nature: 'eu_vat', amount: 0.0)

            elsif order[:accounting_tax] == 'world'
              Tax.find_by(nature: 'import_export_vat', amount: 0.0)
            end
          end

          def find_or_create_baqio_country_tax(tax_line, order)
            country_tax_id = tax_line.first[:country_tax_id].to_i
            # tax already present in Ekylibre with Baqio provider
            tax = Tax.of_provider_vendor(@vendor).of_provider_data(:id, country_tax_id.to_s).first
            unless tax
              # Case 'EU particular sale'
              # https://www.comprendrelacompta.com/achat-vente-biens-hors-france/
              if order[:accounting_tax] == 'eu' || Integrations::Baqio::Handlers::CountryTaxes::EU_CT_CODE.include?(order[:accounting_tax])
                # for person
                if order[:customer][:billing_information][:legal_form].blank? && order[:customer][:billing_information][:vat_number].blank?
                  tax = Integrations::Baqio::Handlers::CountryTaxes.new(vendor: @vendor).find_or_create_specific_tax(country_tax_id)
                # for enterprise
                else
                  tax = Tax.find_by(nature: 'eu_vat', amount: 0.0)
                end
              else
                nil
              end
            end
            tax
          end

      end
    end
  end
end
