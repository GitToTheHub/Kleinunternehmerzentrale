class CreateAssetPrivateUses < ActiveRecord::Migration[8.1]
  def change
    create_table :asset_private_uses do |t|
      t.references :business_asset, null: false, foreign_key: true
      t.integer :year, null: false
      t.decimal :business_percent, precision: 5, scale: 2, null: false
      t.text :basis, null: false
      t.string :calculation_mode, null: false, default: "depreciation"
      t.decimal :manual_amount, precision: 12, scale: 2
      t.timestamps
    end
    add_index :asset_private_uses, [ :business_asset_id, :year ], unique: true
  end
end
