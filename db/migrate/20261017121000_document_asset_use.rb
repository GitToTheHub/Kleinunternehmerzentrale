class DocumentAssetUse < ActiveRecord::Migration[8.1]
  def change
    add_column :business_assets, :business_use_percent, :decimal, precision: 5, scale: 2, default: 100, null: false
    add_column :business_assets, :usage_basis, :text
  end
end
