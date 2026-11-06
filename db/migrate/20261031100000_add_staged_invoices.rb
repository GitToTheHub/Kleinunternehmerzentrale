class AddStagedInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :billing_kind, :string, null: false, default: "regular"
    add_reference :invoices, :billing_root, foreign_key: { to_table: :invoices }
    add_column :invoices, :deducted_payments, :json, null: false, default: []
  end
end
