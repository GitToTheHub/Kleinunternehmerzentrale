class AddCashAllocationToBookkeepingEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :bookkeeping_entries, :cash_usage, :string
    add_column :bookkeeping_entries, :cash_private_amount, :decimal, precision: 12, scale: 2
  end
end
