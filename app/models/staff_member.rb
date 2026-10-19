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

  validates :staff_type,
    presence: true,
    inclusion: { in: STAFF_TYPES }

  validates :access_level, presence: true, inclusion: { in: ACCESS_LEVELS }
  validate :clinician_access_requires_clinician_staff_type

  validates :user_id, uniqueness: { scope: :practice_id }

  def clinician_access_requires_clinician_staff_type
    return unless access_level == "staff_clinician"
    return if staff_type.in?(%w[doctor nurse])

    errors.add(:access_level, "is only available to doctors and nurses")
  end

  def full_name
    [ first_name, last_name ].compact_blank.join(" ")
  end
end
