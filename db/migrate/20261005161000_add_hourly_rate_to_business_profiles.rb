class AddHourlyRateToBusinessProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :business_profiles, :hourly_rate, :decimal, precision: 12, scale: 2
  end
end
