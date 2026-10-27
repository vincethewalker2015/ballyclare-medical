class RecoverGuestRefundsJob < ApplicationJob
  queue_as :default

  def perform
    Payment.where(provider: "stripe", status: "requires_refund", appointment_id: nil)
      .where.not(guest_booking_id: nil)
      .where.not(provider_payment_id: nil)
      .find_each do |payment|
        recover(payment)
      rescue StandardError => error
        Rails.logger.error(
          "Failed to recover guest refund payment=#{payment.id}: #{error.class}: #{error.message}"
        )
      end
  end

  private

  def recover(payment)
    refund = nil

    payment.with_lock do
      return unless payment.status == "requires_refund" && payment.appointment_id.nil?

      # A failed/cancelled refund may already exist at Stripe; require review
      # instead of issuing another refund with a different idempotency key.
      if payment.refunds.where(status: %w[failed cancelled]).exists?
        Rails.logger.warn("Guest refund needs manual review: payment=#{payment.id}")
        return
      end

      remaining = payment.amount_cents -
        payment.refunds.where(status: Payments::CreateRefund::COUNTED_STATUSES).sum(:amount_cents)

      if remaining.positive?
        refund = Payments::CreateRefund.new(
          payment: payment,
          amount_cents: remaining,
          reason: "Guest payment received after appointment became unavailable"
        ).call
      else
        refund = payment.refunds.where(status: "pending").first
      end
    end

    ProcessRefundJob.perform_later(refund.id) if refund&.status == "pending"
  end
end
