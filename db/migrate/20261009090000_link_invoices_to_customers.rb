class LinkInvoicesToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_reference :invoices, :customer, foreign_key: true
  end
end
