class CreatePatients < ActiveRecord::Migration[8.1]
  def change
    create_table :patients, id: :uuid do |t|
      t.references :practice, null: false, foreign_key: true, type: :uuid
      t.references :user, null: true, foreign_key: true, type: :uuid, index: false
      t.string :patient_number, null: false
      t.string :title
      t.string :first_name, null: false
      t.string :middle_names
      t.string :last_name, null: false
      t.date :date_of_birth, null: false
      t.string :sex_at_birth
      t.string :gender_identity
      t.string :phone
      t.string :email
      t.string :address_line_1
      t.string :address_line_2
      t.string :city
      t.string :county
      t.string :postcode
      t.string :country_code
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :patients, [ :practice_id, :patient_number ], unique: true
    add_index :patients, [ :practice_id, :last_name, :date_of_birth ]
    add_index :patients, :user_id, unique: true, where: "user_id IS NOT NULL"
  end
end
