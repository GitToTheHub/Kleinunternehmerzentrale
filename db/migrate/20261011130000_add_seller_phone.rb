class AddSellerPhone < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :seller_phone, :string
    add_column :business_profiles, :phone, :string
  end
end
