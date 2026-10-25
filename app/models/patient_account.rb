class PatientAccount < ApplicationRecord
  has_many :patient_account_links, dependent: :restrict_with_error
  has_one :patient_registration_request, dependent: :restrict_with_error
  devise :database_authenticatable,
    :registerable,
    :recoverable,
    :rememberable,
    :validatable,
    :confirmable
end
