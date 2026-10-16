class AvailabilityBlock < ApplicationRecord
  belongs_to :practice
  belongs_to :clinician, class_name: "StaffMember"

  has_many :appointment_slots, dependent: :restrict_with_error

  validates :starts_at, :ends_at, presence: true
  validates :slot_duration_minutes,
    numericality: { only_integer: true, greater_than: 0 }

  validate :ends_after_it_starts
  validate :does_not_overlap_existing_appointments

  scope :active, -> { where(cancelled_at: nil) }
  scope :cancelled, -> { where.not(cancelled_at: nil) }

  def active?
    cancelled_at.nil?
  end

  def cancelled?
    cancelled_at.present?
  end

  private

  def ends_after_it_starts
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after starts_at") if ends_at <= starts_at
  end

  def does_not_overlap_existing_appointments
    return if cancelled? || clinician_id.blank?
    return if starts_at.blank? || ends_at.blank?
    return if ends_at <= starts_at

    conflicting_appointment = Appointment
      .joins(:appointment_slot)
      .where(appointment_slots: { clinician_id: clinician_id })
      .where(
        "appointment_slots.starts_at < ? AND appointment_slots.ends_at > ?",
        ends_at,
        starts_at
      )
      .exists?

    if conflicting_appointment
      errors.add(
        :base,
        "Availability overlaps an existing appointment."
      )
    end
  end
end
