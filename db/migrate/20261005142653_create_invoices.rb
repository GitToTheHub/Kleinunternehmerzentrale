class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.string :invoice_number
      t.date :issued_on
      t.date :service_on
      t.string :seller_name
      t.string :seller_street
      t.string :seller_postal_code
      t.string :seller_city
      t.string :seller_country
      t.string :seller_email
      t.string :seller_tax_identifier
      t.string :seller_tax_id_kind
      t.string :seller_vat_id
      t.string :buyer_name
      t.string :buyer_street
      t.string :buyer_postal_code
      t.string :buyer_city
      t.string :buyer_country
      t.string :buyer_email
      t.string :buyer_reference
      t.string :payment_terms

      t.timestamps
    end

    add_index :invoices, :invoice_number, unique: true
  end
end
