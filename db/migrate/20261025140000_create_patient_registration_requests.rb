class CreatePatientRegistrationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :patient_registration_requests, id: :uuid do |t|
      t.references :practice, null: false, type: :uuid, foreign_key: true
      t.references :patient_account, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.timestamps null: false
    end
  end
end
