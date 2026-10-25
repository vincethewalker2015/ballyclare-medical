class CreatePatientRegistrationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :patient_registration_requests, id: :uuid do |t|
      t.references :practice, null: false, type: :uuid, foreign_key: true
      t.references :patient_account, null: false, type: :uuid, foreign_key: true
      t.timestamps null: false
    end

    add_index :patient_registration_requests, :patient_account_id, unique: true,
      name: "index_patient_registration_requests_on_account_unique"
  end
end
