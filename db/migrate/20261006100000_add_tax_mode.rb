class AddTaxMode < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :tax_mode, :string, null: false, default: "small_business"
    add_column :invoice_lines, :tax_rate, :decimal, precision: 5, scale: 2, null: false, default: 0
    add_column :business_profiles, :tax_mode, :string, null: false, default: "small_business"
  end
end
