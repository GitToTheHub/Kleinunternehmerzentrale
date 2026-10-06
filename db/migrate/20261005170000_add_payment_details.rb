class AddPaymentDetails < ActiveRecord::Migration[8.1]
  def change
    add_column :business_profiles, :iban, :string
    add_column :business_profiles, :bic, :string
    add_column :invoices, :iban, :string
    add_column :invoices, :bic, :string
    add_column :invoices, :payment_due_on, :date
  end
end
