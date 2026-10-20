class StaffMember < ApplicationRecord
  STAFF_TYPES = %w[doctor nurse administrator].freeze
  ACCESS_LEVELS = %w[staff staff_clinician staff_admin senior_staff_admin].freeze

  belongs_to :practice
  belongs_to :user

  has_many :availability_blocks,
    foreign_key: :clinician_id,
    dependent: :restrict_with_error

  has_many :appointment_slots,
    foreign_key: :clinician_id,
    dependent: :restrict_with_error

  has_many :appointments,
    foreign_key: :clinician_id,
    dependent: :restrict_with_error

  has_many :encounters,
    foreign_key: :clinician_id,
    dependent: :restrict_with_error

  has_many :clinical_notes,
    foreign_key: :author_id,
    dependent: :restrict_with_error

  before_validation :normalise_registration_number

  validates :staff_type,
    presence: true,
    inclusion: { in: STAFF_TYPES }

  validates :access_level, presence: true, inclusion: { in: ACCESS_LEVELS }
  validates :first_name, :last_name, presence: true
  validate :clinician_access_requires_clinician_staff_type

  validates :user_id, uniqueness: { scope: :practice_id }

  # Operational access excludes basic staff. Clinical access will be used
  # when consultation notes, tests and medical records gain staff routes.
  def operational_access?
    access_level.in?(%w[staff_admin staff_clinician senior_staff_admin])
  end

  def clinical_access?
    access_level.in?(%w[staff_clinician senior_staff_admin])
  end

  def staff_administration_access?
    access_level.in?(%w[staff_admin senior_staff_admin])
  end

  def senior_administration_access?
    access_level == "senior_staff_admin"
  end

  def clinician_access_requires_clinician_staff_type
    return unless access_level == "staff_clinician"
    return if staff_type.in?(%w[doctor nurse])

    errors.add(:access_level, "is only available to doctors and nurses")
  end

  def normalise_registration_number
    self.registration_number = registration_number.presence
  end

  def full_name
    [ first_name, last_name ].compact_blank.join(" ")
  end
end
