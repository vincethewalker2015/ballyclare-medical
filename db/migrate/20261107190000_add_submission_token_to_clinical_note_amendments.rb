class AddSubmissionTokenToClinicalNoteAmendments < ActiveRecord::Migration[8.1]
  def change
    add_column :clinical_note_amendments, :submission_token, :string
    add_index :clinical_note_amendments, [ :clinical_note_id, :submission_token ],
      unique: true, name: "index_clinical_note_amendments_on_note_and_submission"
  end
end
