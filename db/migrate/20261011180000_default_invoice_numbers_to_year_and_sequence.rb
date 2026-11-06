class DefaultInvoiceNumbersToYearAndSequence < ActiveRecord::Migration[8.1]
  def change
    old_format = "[Jahr]-[Monat]-[Tag]-[Fortlaufendenummer]"
    new_format = "RE-[Jahr]-[Fortlaufendenummer]"
    change_column_default :invoices, :invoice_number_format, from: old_format, to: new_format
    change_column_default :business_profiles, :invoice_number_format, from: old_format, to: new_format
  end
end
