class AddServiceUntilToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :service_until_on, :date
  end
end
