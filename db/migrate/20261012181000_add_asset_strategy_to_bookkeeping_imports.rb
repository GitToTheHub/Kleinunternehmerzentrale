class AddAssetStrategyToBookkeepingImports < ActiveRecord::Migration[8.1]
  def change
    add_column :bookkeeping_imports, :assets_managed_separately, :boolean, null: false, default: false
  end
end
