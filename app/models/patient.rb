class Patient < ApplicationRecord
  PATIENT_TYPES = %w[practice external].freeze

  belongs_to :practice
  belongs_to :user, optional: true
  has_one :patient_account_link, dependent: :restrict_with_error

  has_many :patient_identifiers, dependent: :destroy
  has_many :appointments, dependent: :restrict_with_error
  has_many :appointment_holds, dependent: :restrict_with_error
  has_many :encounters, dependent: :restrict_with_error
  has_many :clinical_notes, dependent: :restrict_with_error
  has_many :payments, dependent: :restrict_with_error

  before_validation :assign_patient_number, on: :create

  validate :patient_number_cannot_change, on: :update

  validates :patient_type, inclusion: { in: PATIENT_TYPES }

  validates :patient_number, :first_name, :last_name, :date_of_birth,
    presence: true

  validates :patient_number,
    uniqueness: { scope: :practice_id }

  # A matching name and date of birth is a prompt for identity review, not proof
  # that two people are the same. Never search outside the selected practice.
  def self.possible_existing_for(practice:, first_name:, last_name:, date_of_birth:)
    return none if practice.blank? || [ first_name, last_name, date_of_birth ].any?(&:blank?)

    practice.patients.where(date_of_birth: date_of_birth)
      .where("LOWER(TRIM(first_name)) = ? AND LOWER(TRIM(last_name)) = ?",
        first_name.strip.downcase, last_name.strip.downcase)
  end
  private

  def assign_patient_number
    self.patient_number = "P#{SecureRandom.hex(6).upcase}" if patient_number.blank?
  end

  def patient_number_cannot_change
    errors.add(:patient_number, "cannot be changed") if will_save_change_to_patient_number?
  end
end
