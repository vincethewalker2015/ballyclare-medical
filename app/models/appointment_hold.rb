class AppointmentHold < ApplicationRecord
  belongs_to :appointment_slot
  belongs_to :patient, optional: true
  belongs_to :guest_booking, optional: true

  validate :exactly_one_booking_owner

  has_many :payments, dependent: :restrict_with_error

  validates :expires_at, presence: true

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where(expires_at: ..Time.current) }

  def exactly_one_booking_owner
    errors.add(:base, "A hold must belong to either a patient or a guest booking") if patient.present? == guest_booking.present?
  end

  def expired?
    expires_at <= Time.current
  end
end
