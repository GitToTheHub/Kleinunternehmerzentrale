class CreateEuerExpensePolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :euer_expense_policies do |t|
      t.references :workspace, null: false, foreign_key: true
      t.integer :year, null: false
      t.string :deduction_method, null: false, default: "actual"
      t.boolean :eligibility_confirmed, null: false, default: false
      t.timestamps
    end
    add_index :euer_expense_policies, [ :workspace_id, :year ], unique: true
  end
end
