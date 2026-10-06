class AddCancelledInvoiceToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_reference :invoices, :cancelled_invoice, foreign_key: { to_table: :invoices }, index: { unique: true }
  end
end
