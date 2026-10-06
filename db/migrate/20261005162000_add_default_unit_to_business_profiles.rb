class AddDefaultUnitToBusinessProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :business_profiles, :default_unit_code, :string
  end
end
