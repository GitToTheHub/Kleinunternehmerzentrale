class AddInvoicePaymentDetails < ActiveRecord::Migration[8.1]
  def up
    add_column :invoices, :payment_method, :string
    add_column :invoices, :paid, :boolean, default: false, null: false
    execute "UPDATE invoices SET payment_method = 'cash', paid = TRUE WHERE LOWER(TRIM(payment_terms)) IN ('die rechnung wurde bar bezahlt', 'die rechnung wurde bar bezahlt.') AND cancelled_invoice_id IS NULL"
  end

  def down
    remove_column :invoices, :paid
    remove_column :invoices, :payment_method
  end
end
