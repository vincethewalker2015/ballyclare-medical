class CreatePractices < ActiveRecord::Migration[8.1]
  def change
    create_table :practices, id: :uuid do |t|
      t.string :name, null: false
      t.string :phone
      t.string :email
      t.string :currency, null: false
      t.string :timezone, null: false
      t.string :address_line_1
      t.string :address_line_2
      t.string :city
      t.string :region
      t.string :postal_code
      t.string :country_code, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :practices, :name, unique: true
  end
end
