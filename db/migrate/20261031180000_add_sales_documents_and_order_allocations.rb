class AddSalesDocumentsAndOrderAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :sales_documents do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :document_number, null: false
      t.integer :number_sequence, null: false
      t.date :document_date, null: false
      t.json :data, null: false, default: {}
      t.decimal :total_amount, precision: 14, scale: 2, null: false
      t.references :source_offer, foreign_key: { to_table: :sales_documents }, index: { unique: true }
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :sales_documents, [ :workspace_id, :document_number ], unique: true
    add_reference :invoices, :sales_document, foreign_key: true
    add_column :invoices, :order_snapshot, :json, null: false, default: {}
    add_column :invoices, :allocation_mode, :string
    add_column :invoices, :allocation_percent, :decimal, precision: 7, scale: 2
    add_column :invoices, :allocation_amount, :decimal, precision: 14, scale: 2
  end
end
