class AddReviewToPatientRegistrationRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :patient_registration_requests, :review_status, :string, null: false, default: "awaiting_review"
    add_column :patient_registration_requests, :patient_route, :string
    add_reference :patient_registration_requests, :selected_patient, type: :uuid,
      foreign_key: { to_table: :patients }
    add_reference :patient_registration_requests, :reviewed_by, type: :uuid,
      foreign_key: { to_table: :staff_members }
    add_column :patient_registration_requests, :verification_method, :string
    add_column :patient_registration_requests, :identity_verified_at, :datetime
    add_reference :patient_registration_requests, :approved_by, type: :uuid,
      foreign_key: { to_table: :staff_members }
    add_column :patient_registration_requests, :approved_at, :datetime
    add_column :patient_registration_requests, :processed_at, :datetime
  end
end
