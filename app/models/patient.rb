class Patient < ApplicationRecord
  belongs_to :practice
  belongs_to :user, optional: true

  has_many :patient_identifiers, dependent: :destroy
  has_many :appointments, dependent: :restrict_with_error
  has_many :appointment_holds, dependent: :restrict_with_error
  has_many :encounters, dependent: :restrict_with_error
  has_many :clinical_notes, dependent: :restrict_with_error
  has_many :payments, dependent: :restrict_with_error

  validates :patient_number, :first_name, :last_name, :date_of_birth,
    presence: true

  validates :patient_number,
    uniqueness: { scope: :practice_id }
end
