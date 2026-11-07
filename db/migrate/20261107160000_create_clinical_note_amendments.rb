class CreateClinicalNoteAmendments < ActiveRecord::Migration[8.1]
  def change
    create_table :clinical_note_amendments, id: :uuid do |t|
      t.references :clinical_note, null: false, type: :uuid, foreign_key: true
      t.references :author, null: false, type: :uuid, foreign_key: { to_table: :staff_members }
      t.string :reason, null: false
      t.text :body, null: false

      t.timestamps
    end

    add_index :clinical_note_amendments, [ :clinical_note_id, :created_at ],
      name: "index_clinical_note_amendments_on_note_and_created_at"
  end
end
