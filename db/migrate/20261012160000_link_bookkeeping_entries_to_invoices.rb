class LinkBookkeepingEntriesToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_reference :bookkeeping_entries, :invoice, foreign_key: true, index: { unique: true }
  end
end
