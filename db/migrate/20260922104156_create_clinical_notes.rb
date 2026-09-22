class CreateClinicalNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :clinical_notes, id: :uuid do |t|
      t.references :patient,
        type: :uuid,
        null: false,
        foreign_key: true

      t.references :encounter,
        type: :uuid,
        null: false,
        foreign_key: true

      t.references :author,
        type: :uuid,
        null: false,
        foreign_key: { to_table: :staff_members }

      t.string :note_type, null: false
      t.text :body, null: false

      t.timestamps
    end

    add_index :clinical_notes,
      [ :patient_id, :created_at ]

    add_index :clinical_notes,
      [ :author_id, :created_at ]

    add_index :clinical_notes,
      [ :encounter_id, :created_at ]
  end
end
