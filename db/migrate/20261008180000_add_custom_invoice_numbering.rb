class AddCustomInvoiceNumbering < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :invoice_number_format, :string, default: "RE-[Jahr]-[Nummer]", null: false
    add_column :invoices, :invoice_number_sequence, :integer
    add_column :invoices, :buyer_abbreviation, :string
    add_column :business_profiles, :invoice_number_format, :string, default: "RE-[Jahr]-[Nummer]", null: false
    add_column :customers, :invoice_abbreviation, :string
  end
end
