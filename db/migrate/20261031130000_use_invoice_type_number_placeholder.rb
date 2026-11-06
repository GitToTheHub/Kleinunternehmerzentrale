class UseInvoiceTypeNumberPlaceholder < ActiveRecord::Migration[8.1]
  def change
    %i[invoices business_profiles].each do |table|
      change_column_default table, :invoice_number_format,
        from: "RE-[Jahr]-[Fortlaufendenummer]", to: "[Rechnungstyp]-[Jahr]-[Fortlaufendenummer]"
    end
  end
end
