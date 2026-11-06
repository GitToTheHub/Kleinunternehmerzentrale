class CreateBookkeepingEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :bookkeeping_entries do |t|
      t.references :workspace, null: false, foreign_key: true
      t.date :paid_on, null: false
      t.string :kind, null: false
      t.string :description, null: false
      t.string :reference
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.timestamps
    end
    add_index :bookkeeping_entries, [ :workspace_id, :paid_on ]
  end
end
