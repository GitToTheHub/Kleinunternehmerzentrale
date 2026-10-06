class CreateInvoiceLines < ActiveRecord::Migration[8.1]
  def change
    create_table :invoice_lines do |t|
      t.references :invoice, null: false, foreign_key: true
      t.string :description
      t.decimal :quantity, precision: 12, scale: 3
      t.decimal :unit_price, precision: 12, scale: 2
      t.string :unit_code

      t.timestamps
    end
  end
end
