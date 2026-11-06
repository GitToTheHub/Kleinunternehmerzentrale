class UseIntegerIdsForInvoiceDrafts < ActiveRecord::Migration[8.1]
  def up
    rename_table :invoice_drafts, :legacy_invoice_drafts
    create_table :invoice_drafts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.json :data, null: false, default: {}
      t.string :status, null: false, default: "active"
      t.string :form_token, null: false
      t.timestamps
    end
    add_index :invoice_drafts, [ :workspace_id, :status, :updated_at ]
    add_index :invoice_drafts, [ :workspace_id, :form_token ], unique: true

    legacy = Class.new(ActiveRecord::Base) { self.table_name = "legacy_invoice_drafts" }
    draft = Class.new(ActiveRecord::Base) { self.table_name = "invoice_drafts" }
    legacy.order(:created_at, :id).each do |record|
      draft.create!(record.attributes.except("id").merge("form_token" => record.id))
    end
    drop_table :legacy_invoice_drafts
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
