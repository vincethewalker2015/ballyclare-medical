class AppointmentStatusChange < ApplicationRecord
  belongs_to :appointment
  belongs_to :changed_by, class_name: "User"

  validates :to_status,
    presence: true,
    inclusion: { in: Appointment::STATUSES }

  validates :from_status,
    inclusion: { in: Appointment::STATUSES },
    allow_nil: true
end
