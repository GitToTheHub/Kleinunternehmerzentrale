module InvoiceInput
  extend ActiveSupport::Concern

  private

  def invoice_params
    params.require(:invoice).permit(
      :order_based, :sales_document_id, :allocation_basis, :allocation_mode, :allocation_percent, :allocation_amount, :billing_kind, :billing_root_id, :corrected_invoice_id, :payment_method, :paid, :received_on, :received_account, :received_amount, :title, :currency, :exchange_rate, :exchange_rate_quote, :exchange_rate_on, :exchange_rate_source, :issued_on, :service_on, :service_until_on, :service_period, :invoice_number_start, :invoice_number_last, :invoice_number_format, :invoice_number_format_once, :buyer_abbreviation, :seller_name, :seller_street, :seller_postal_code,
      :seller_city, :seller_country, :seller_email, :seller_phone, :seller_tax_identifier, :seller_hourly_rate,
      :customer_id, :customer_update_mode, :buyer_hourly_rate, :buyer_name, :buyer_contact_name, :buyer_street, :buyer_postal_code,
      :buyer_city, :buyer_country, :buyer_email, :buyer_leitweg_id, :buyer_order_number, :payment_terms, :tax_mode, :iban, :bic, :payment_due_on,
      settlement_invoice_ids: [],
      position_allocations: [ :mode, :value ],
      invoice_lines_attributes: %i[id description details quantity unit_price unit_code tax_rate _destroy]
    )
  end
end
