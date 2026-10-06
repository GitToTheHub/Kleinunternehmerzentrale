class CreateWorkspaces < ActiveRecord::Migration[8.1]
  TABLES = %i[invoices customers business_profiles].freeze

  def up
    create_table :workspaces do |t|
      t.string :token, null: false
      t.string :email
      t.string :password_digest
      t.datetime :last_active_at, null: false
      t.timestamps
    end
    add_index :workspaces, :token, unique: true
    add_index :workspaces, :email, unique: true
    add_index :workspaces, :last_active_at

    TABLES.each { |table| add_reference table, :workspace, foreign_key: true }

    # Bestehende Daten gehören dem ersten Arbeitsbereich, damit nichts verloren geht.
    if TABLES.any? { |table| select_value("SELECT 1 FROM #{table} LIMIT 1") }
      execute "INSERT INTO workspaces (token, last_active_at, created_at, updated_at) VALUES ('#{SecureRandom.base58(24)}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
      id = select_value("SELECT id FROM workspaces LIMIT 1")
      TABLES.each { |table| execute "UPDATE #{table} SET workspace_id = #{id}" }
    end

    TABLES.each { |table| change_column_null table, :workspace_id, false }
    remove_index :invoices, :invoice_number if index_exists?(:invoices, :invoice_number)
    add_index :invoices, %i[workspace_id invoice_number], unique: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
