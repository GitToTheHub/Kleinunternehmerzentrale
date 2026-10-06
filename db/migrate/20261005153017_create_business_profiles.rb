class CreateBusinessProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :business_profiles do |t|
      t.string :name
      t.string :street
      t.string :postal_code
      t.string :city
      t.string :country
      t.string :email
      t.string :tax_identifier

      t.timestamps
    end
  end
end
