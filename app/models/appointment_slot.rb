class AppointmentSlot < ApplicationRecord
  belongs_to :practice
  belongs_to :clinician, class_name: "StaffMember"
  belongs_to :availability_block

  has_one :appointment, dependent: :restrict_with_error
  has_one :appointment_hold, dependent: :destroy

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_it_starts

  scope :upcoming, -> { where(starts_at: Time.current..) }

  private

  def ends_after_it_starts
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after starts_at") if ends_at <= starts_at
  end
end
