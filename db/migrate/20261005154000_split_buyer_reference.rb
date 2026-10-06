class SplitBuyerReference < ActiveRecord::Migration[8.1]
  def change
    rename_column :invoices, :buyer_reference, :buyer_leitweg_id
    add_column :invoices, :buyer_order_number, :string
    rename_column :customers, :reference, :leitweg_id
  end
end
