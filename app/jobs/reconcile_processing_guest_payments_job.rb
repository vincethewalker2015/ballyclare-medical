class ReconcileProcessingGuestPaymentsJob < ApplicationJob
  queue_as :default

  def perform
    Payment.where(provider: "stripe", status: "processing")
      .where.not(guest_booking_id: nil)
      .where(appointment_id: nil)
      .where.not(provider_payment_id: nil)
      .where("payments.updated_at <= ?", 1.minute.ago)
      .find_each do |payment|
        Payments::ReconcileStripeStatus.new(payment: payment).call
      rescue Stripe::StripeError => error
        Rails.logger.warn("Guest payment reconciliation failed: payment=#{payment.id} error=#{error.class}")
      end
  end
end
