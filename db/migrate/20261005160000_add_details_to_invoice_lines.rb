class AddDetailsToInvoiceLines < ActiveRecord::Migration[8.1]
  def change
    add_column :invoice_lines, :details, :text
  end
end
