class CreatePatientAccountLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :patient_account_links, id: :uuid do |t|
      t.references :practice, null: false, type: :uuid, foreign_key: true
      t.references :patient, null: false, type: :uuid, foreign_key: true
      t.references :patient_account, null: false, type: :uuid, foreign_key: true
      t.references :verified_by, type: :uuid, foreign_key: { to_table: :staff_members }
      t.string :status, null: false, default: "pending"
      t.string :verification_method
      t.datetime :verified_at
      t.datetime :approved_at
      t.timestamps null: false
    end

    add_index :patient_account_links, [ :practice_id, :patient_account_id ],
      unique: true, name: "index_patient_account_links_on_practice_and_account"
    add_index :patient_account_links, :patient_id, unique: true
    add_check_constraint :patient_account_links,
      "status IN ('pending', 'approved', 'revoked')",
      name: "patient_account_links_valid_status"
    add_check_constraint :patient_account_links,
      "status <> 'approved' OR (verified_by_id IS NOT NULL AND verified_at IS NOT NULL AND approved_at IS NOT NULL AND verification_method IS NOT NULL)",
      name: "patient_account_links_approval_requires_verification"
  end
end
