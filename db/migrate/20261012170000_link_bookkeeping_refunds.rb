class LinkBookkeepingRefunds < ActiveRecord::Migration[8.1]
  def change
    add_reference :bookkeeping_entries, :original_entry, foreign_key: { to_table: :bookkeeping_entries }
  end
end
