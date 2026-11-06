class AddInvoiceCurrency < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :currency, :string, default: "EUR", null: false
    add_column :invoices, :exchange_rate, :decimal, precision: 18, scale: 8
    add_column :invoices, :exchange_rate_on, :date
    add_column :invoices, :exchange_rate_source, :string
  end
end
