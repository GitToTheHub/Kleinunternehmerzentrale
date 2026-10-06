class AddPaymentDefaultsToCustomers < ActiveRecord::Migration[8.1]
  def change
    # nil bedeutet: keine Zahlungsfrist auf Rechnungen an diesen Kunden
    add_column :customers, :payment_due_days, :integer, default: 14
    add_column :customers, :payment_terms, :string
  end
end
