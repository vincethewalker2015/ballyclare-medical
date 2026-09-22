class Appointment < ApplicationRecord
  STATUSES = %w[
    booked
    confirmed
    arrived
    in_consultation
    completed
    cancelled
    referred
    did_not_attend
  ].freeze

  belongs_to :practice
  belongs_to :appointment_slot
  belongs_to :patient
  belongs_to :clinician, class_name: "StaffMember"
  belongs_to :cancelled_by, class_name: "User", optional: true

  has_many :appointment_status_changes, dependent: :restrict_with_error
  has_many :payments, dependent: :restrict_with_error
  has_one :encounter, dependent: :restrict_with_error

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :booked_at, presence: true
end
