class AddApplicantDetailsToPatientRegistrationRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :patient_registration_requests, :first_name, :string
    add_column :patient_registration_requests, :last_name, :string
    add_column :patient_registration_requests, :date_of_birth, :date
  end
end
