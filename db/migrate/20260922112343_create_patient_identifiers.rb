class CreatePatientIdentifiers < ActiveRecord::Migration[8.1]
  def change
    create_table :patient_identifiers, id: :uuid do |t|
      t.references :patient,
        type: :uuid,
        null: false,
        foreign_key: true,
        index: false

      t.string :identifier_type, null: false
      t.string :identifier_value, null: false

      t.string :issuing_authority
      t.string :country_code

      t.timestamps
    end

    add_index :patient_identifiers,
      [ :patient_id, :identifier_type, :identifier_value ],
      unique: true,
      name: "index_patient_identifiers_on_patient_type_and_value"

    add_index :patient_identifiers,
      [ :identifier_type, :identifier_value ]
  end
end
