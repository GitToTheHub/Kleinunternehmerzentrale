class AddImportNotesToBookkeepingImports < ActiveRecord::Migration[8.1]
  def change
    add_column :bookkeeping_imports, :notes, :text, null: false, default: ""
  end
end
