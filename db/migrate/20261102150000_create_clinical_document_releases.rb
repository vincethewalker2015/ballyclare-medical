class CreateClinicalDocumentReleases < ActiveRecord::Migration[8.0]
  def change
    create_table :clinical_document_releases, id: :uuid do |t|
      t.references :practice, type: :uuid, null: false, foreign_key: true
      t.references :patient, type: :uuid, null: false, foreign_key: true
      t.references :encounter, type: :uuid, null: false, foreign_key: true
      t.references :released_by, type: :uuid, null: false, foreign_key: { to_table: :staff_members }
      t.string :title, null: false
      t.text :body, null: false
      t.datetime :released_at, null: false
      t.timestamps
    end
    add_index :clinical_document_releases, [ :practice_id, :patient_id, :released_at ],
      name: "index_clinical_releases_for_patient"
  end
end
