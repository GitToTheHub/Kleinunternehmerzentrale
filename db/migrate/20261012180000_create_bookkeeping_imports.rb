class CreateBookkeepingImports < ActiveRecord::Migration[8.1]
  def change
    create_table :bookkeeping_imports do |t|
      t.references :workspace, null: false, foreign_key: true
      t.integer :year, null: false
      t.date :covered_through, null: false
      t.string :source, null: false
      t.json :amounts, null: false, default: {}
      t.timestamps
    end
    add_index :bookkeeping_imports, [ :workspace_id, :year ], unique: true
  end
end
