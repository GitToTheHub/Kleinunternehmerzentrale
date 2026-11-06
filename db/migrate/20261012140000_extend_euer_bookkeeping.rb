class ExtendEuerBookkeeping < ActiveRecord::Migration[8.1]
  def change
    change_table :bookkeeping_entries do |t|
      t.string :category
      t.integer :tax_year
      t.decimal :vat_amount, precision: 12, scale: 2, default: 0, null: false
      t.decimal :deductible_percent, precision: 5, scale: 2
      t.string :payment_account, default: "business", null: false
      t.boolean :reversal, default: false, null: false
    end

    create_table :business_assets do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :name, null: false
      t.string :reference
      t.date :acquired_on, null: false
      t.string :origin, default: "purchase", null: false
      t.string :category, default: "office", null: false
      t.decimal :cost, precision: 12, scale: 2, null: false
      t.string :depreciation_method, default: "linear", null: false
      t.integer :useful_life
      t.decimal :gwg_net_value, precision: 12, scale: 2
      t.date :paid_on
      t.string :payment_account, default: "business", null: false
      t.decimal :input_vat, precision: 12, scale: 2, default: 0, null: false
      t.date :disposed_on
      t.string :disposal_kind
      t.decimal :withdrawal_value, precision: 12, scale: 2
      t.decimal :withdrawal_vat, precision: 12, scale: 2, default: 0, null: false
      t.text :notes
      t.timestamps
    end

    create_table :asset_depreciations do |t|
      t.references :business_asset, null: false, foreign_key: true
      t.integer :year, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.decimal :special_amount, precision: 12, scale: 2, default: 0, null: false
      t.string :reason, null: false
      t.timestamps
    end
    add_index :asset_depreciations, [ :business_asset_id, :year ], unique: true

    create_table :euer_adjustments do |t|
      t.references :workspace, null: false, foreign_key: true
      t.integer :year, null: false
      t.string :field_key, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.text :description, null: false
      t.timestamps
    end
  end
end
