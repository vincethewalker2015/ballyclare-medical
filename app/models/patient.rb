class Patient < ApplicationRecord
  belongs_to :practice
  belongs_to :user, optional: true

  has_many :patient_identifiers, dependent: :destroy
  has_many :appointments, dependent: :restrict_with_error
  has_many :appointment_holds, dependent: :restrict_with_error
  has_many :encounters, dependent: :restrict_with_error
  has_many :clinical_notes, dependent: :restrict_with_error
  has_many :payments, dependent: :restrict_with_error

  before_validation :assign_patient_number, on: :create

  validate :patient_number_cannot_change, on: :update

  validates :patient_number, :first_name, :last_name, :date_of_birth,
    presence: true

  validates :patient_number,
    uniqueness: { scope: :practice_id }
  private

  def assign_patient_number
    self.patient_number = "P#{SecureRandom.hex(6).upcase}" if patient_number.blank?
  end

  def patient_number_cannot_change
    errors.add(:patient_number, "cannot be changed") if will_save_change_to_patient_number?
  end
end
