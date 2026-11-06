class AddTitleToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :title, :string
  end
end
