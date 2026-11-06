class CompleteEuerStatements < ActiveRecord::Migration[8.1]
  def change
    add_column :bookkeeping_imports, :details, :json, null: false, default: {}
    create_table :euer_statements do |t|
      t.references :workspace, null: false, foreign_key: true
      t.integer :year, null: false
      t.json :details, null: false, default: {}
      t.timestamps
    end
    add_index :euer_statements, [ :workspace_id, :year ], unique: true
  end
end
