class UseDailyInvoiceNumberDefault < ActiveRecord::Migration[8.1]
  OLD_FORMAT = "RE-[Jahr]-[Nummer]"
  NEW_FORMAT = "[Jahr]-[Monat]-[Tag]-[Mehrfachrechnungszähler]"

  def up
    add_column :invoices, :invoice_number_daily_sequence, :integer
    change_column_default :invoices, :invoice_number_format, from: OLD_FORMAT, to: NEW_FORMAT
    change_column_default :business_profiles, :invoice_number_format, from: OLD_FORMAT, to: NEW_FORMAT
    execute "UPDATE business_profiles SET invoice_number_format = #{connection.quote(NEW_FORMAT)} WHERE invoice_number_format = #{connection.quote(OLD_FORMAT)}"
  end

  def down
    execute "UPDATE business_profiles SET invoice_number_format = #{connection.quote(OLD_FORMAT)} WHERE invoice_number_format = #{connection.quote(NEW_FORMAT)}"
    change_column_default :business_profiles, :invoice_number_format, from: NEW_FORMAT, to: OLD_FORMAT
    change_column_default :invoices, :invoice_number_format, from: NEW_FORMAT, to: OLD_FORMAT
    remove_column :invoices, :invoice_number_daily_sequence
  end
end
