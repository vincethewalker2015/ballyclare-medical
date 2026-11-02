class AddDraftWorkflowToClinicalNotes < ActiveRecord::Migration[8.0]
  def change
    add_column :clinical_notes, :status, :string, null: false, default: "signed"
    add_column :clinical_notes, :lock_version, :integer, null: false, default: 0
    add_index :clinical_notes, :encounter_id, unique: true,
      where: "status = 'draft' AND note_type = 'consultation'",
      name: "index_one_consultation_draft_per_encounter"
  end
end
