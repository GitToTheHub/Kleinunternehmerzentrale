class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :name
      t.string :street
      t.string :postal_code
      t.string :city
      t.string :country
      t.string :email
      t.string :reference

      t.timestamps
    end
    add_index :customers, :name
  end
end
