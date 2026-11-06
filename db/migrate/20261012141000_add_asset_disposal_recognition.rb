class AddAssetDisposalRecognition < ActiveRecord::Migration[8.1]
  def change
    add_column :business_assets, :disposal_recognized_on, :date
  end
end
