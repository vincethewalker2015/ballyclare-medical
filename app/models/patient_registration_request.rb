class PatientRegistrationRequest < ApplicationRecord
  belongs_to :practice
  belongs_to :patient_account

  validates :patient_account_id, uniqueness: true
end
