class StaffMember < ApplicationRecord
  STAFF_TYPES = %w[doctor nurse admin].freeze

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

  validates :default_appointment_duration,
    numericality: { only_integer: true, greater_than: 0 }
end
