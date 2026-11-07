class AddResumeSectionToInvoiceDrafts < ActiveRecord::Migration[8.1]
  def change
    add_column :invoice_drafts, :resume_section, :string
  end
end
