class Payment < ApplicationRecord
  STATUSES = %w[
    pending
    processing
    succeeded
    failed
    cancelled
    requires_refund
  ].freeze

  belongs_to :appointment, optional: true
  belongs_to :appointment_hold, optional: true
  belongs_to :patient, optional: true
  belongs_to :guest_booking, optional: true

  validate :booking_owner_present

  has_many :refunds, dependent: :restrict_with_error

  def booking_owner_present
    errors.add(:base, "A payment must belong to a patient or guest booking") if patient.nil? && guest_booking.nil?
  end

  validates :provider, :currency, :idempotency_key, presence: true

  validates :amount_cents,
            numericality: {
              only_integer: true,
              greater_than: 0
            }

  validates :status,
            presence: true,
            inclusion: { in: STATUSES }

  validates :idempotency_key, uniqueness: true
end
