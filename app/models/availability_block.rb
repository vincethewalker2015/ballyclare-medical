class AvailabilityBlock < ApplicationRecord
  belongs_to :practice
  belongs_to :clinician, class_name: "StaffMember"

  has_many :appointment_slots, dependent: :restrict_with_error

  validates :starts_at, :ends_at, presence: true
  validates :slot_duration_minutes,
    numericality: { only_integer: true, greater_than: 0 }

  validate :ends_after_it_starts

  private

  def ends_after_it_starts
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after starts_at") if ends_at <= starts_at
  end
end
