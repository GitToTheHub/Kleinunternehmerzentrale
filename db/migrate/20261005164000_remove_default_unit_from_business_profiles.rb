class RemoveDefaultUnitFromBusinessProfiles < ActiveRecord::Migration[8.1]
  def change
    remove_column :business_profiles, :default_unit_code, :string
  end
end
