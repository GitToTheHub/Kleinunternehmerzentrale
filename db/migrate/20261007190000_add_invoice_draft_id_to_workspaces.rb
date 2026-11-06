class AddInvoiceDraftIdToWorkspaces < ActiveRecord::Migration[8.1]
  def up
    add_column :workspaces, :invoice_draft_id, :string
    add_index :workspaces, :invoice_draft_id, unique: true

    workspace = Class.new(ActiveRecord::Base) { self.table_name = "workspaces" }
    workspace.where.not(invoice_draft: nil).find_each do |record|
      record.update_columns(invoice_draft_id: SecureRandom.uuid) if record.invoice_draft.present?
    end
  end

  def down
    remove_column :workspaces, :invoice_draft_id
  end
end
