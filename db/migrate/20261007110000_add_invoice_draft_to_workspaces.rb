class AddInvoiceDraftToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :invoice_draft, :json
    add_column :workspaces, :invoice_draft_updated_at, :datetime
  end
end
