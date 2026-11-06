class CreateInvoiceDrafts < ActiveRecord::Migration[8.1]
  def up
    create_table :invoice_drafts, id: :string do |t|
      t.references :workspace, null: false, foreign_key: true
      t.json :data, null: false, default: {}
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :invoice_drafts, [ :workspace_id, :status, :updated_at ]

    workspace = Class.new(ActiveRecord::Base) { self.table_name = "workspaces" }
    draft = Class.new(ActiveRecord::Base) { self.table_name = "invoice_drafts" }
    workspace.where.not(invoice_draft: nil).find_each do |record|
      next if record.invoice_draft.blank?

      saved_at = record.invoice_draft_updated_at || Time.current
      draft.create!(id: record.invoice_draft_id.presence || SecureRandom.uuid, workspace_id: record.id,
                    data: record.invoice_draft, created_at: saved_at, updated_at: saved_at)
      record.update_columns(invoice_draft: nil, invoice_draft_id: nil, invoice_draft_updated_at: nil)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Mehrere Entwürfe können nicht verlustfrei in einen einzelnen Entwurf zurückgeführt werden."
  end
end
