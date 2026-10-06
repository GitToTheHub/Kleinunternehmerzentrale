class AddHourlyRateToCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :hourly_rate, :decimal, precision: 12, scale: 2
  end
end
