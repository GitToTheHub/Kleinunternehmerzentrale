class AddHomeOfficeToEuerExpensePolicies < ActiveRecord::Migration[8.1]
  def change
    add_column :euer_expense_policies, :home_office_method, :string, null: false, default: "none"
    add_column :euer_expense_policies, :home_days, :integer, null: false, default: 0
    add_column :euer_expense_policies, :home_months, :integer, null: false, default: 0
    add_column :euer_expense_policies, :home_eligibility_confirmed, :boolean, null: false, default: false
    add_column :euer_expense_policies, :home_basis, :text
  end
end
