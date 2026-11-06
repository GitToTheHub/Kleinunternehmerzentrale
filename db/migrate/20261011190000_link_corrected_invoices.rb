class LinkCorrectedInvoices < ActiveRecord::Migration[8.1]
  def change
    add_reference :invoices, :corrected_invoice, foreign_key: { to_table: :invoices }
  end
end
