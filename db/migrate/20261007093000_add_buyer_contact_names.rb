class AddBuyerContactNames < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :buyer_contact_name, :string
    add_column :customers, :contact_name, :string
  end
end
