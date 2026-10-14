class Refund < ApplicationRecord
  STATUSES = %w[pending processing succeeded failed cancelled].freeze

  belongs_to :payment

  after_update_commit :broadcast_appointment_refresh, if: :saved_change_to_status?

  belongs_to :requested_by,
             class_name: "User",
             optional: true

  validates :amount_cents,
            numericality: {
              only_integer: true,
              greater_than: 0
            }

  validates :currency, :requested_at, :idempotency_key,
            presence: true

  validates :idempotency_key,
            uniqueness: true

  validates :status,
            presence: true,
            inclusion: { in: STATUSES }
  private

  def broadcast_appointment_refresh
    broadcast_refresh_later_to(payment.appointment)
  end
end
