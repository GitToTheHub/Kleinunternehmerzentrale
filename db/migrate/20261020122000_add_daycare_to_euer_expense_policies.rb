class AddDaycareToEuerExpensePolicies < ActiveRecord::Migration[8.1]
  def change
    add_column :euer_expense_policies, :daycare_rows, :json, null: false, default: []
    add_column :euer_expense_policies, :daycare_eligibility_confirmed, :boolean, null: false, default: false
  end
end
