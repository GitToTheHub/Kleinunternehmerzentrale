class RenameInvoiceSequencePlaceholder < ActiveRecord::Migration[8.1]
  def up
    rename_placeholder("[Nummer]", "[Fortlaufendenummer]")
  end

  def down
    rename_placeholder("[Fortlaufendenummer]", "[Nummer]")
  end

  private

  def rename_placeholder(from, to)
    old_token, new_token = connection.quote(from), connection.quote(to)
    %w[invoices business_profiles].each do |table|
      execute "UPDATE #{table} SET invoice_number_format = REPLACE(invoice_number_format, #{old_token}, #{new_token}) WHERE INSTR(invoice_number_format, #{old_token}) > 0"
    end
    { "invoice_drafts" => "data", "workspaces" => "invoice_draft" }.each do |table, column|
      path = connection.quote("$.invoice_number_format")
      value = "JSON_EXTRACT(#{column}, #{path})"
      execute "UPDATE #{table} SET #{column} = JSON_SET(#{column}, #{path}, REPLACE(#{value}, #{old_token}, #{new_token})) WHERE JSON_TYPE(#{column}, #{path}) = 'text' AND INSTR(#{value}, #{old_token}) > 0"
    end
  end
end
