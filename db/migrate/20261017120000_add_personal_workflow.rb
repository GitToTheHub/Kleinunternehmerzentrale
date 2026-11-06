class AddPersonalWorkflow < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :workflow_settings, :json, default: {}, null: false
    add_column :bookkeeping_entries, :business_percent, :decimal, precision: 5, scale: 2, default: 100, null: false
    add_column :bookkeeping_entries, :usage_notes, :text
  end
end
