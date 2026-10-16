require "zlib"

class ReconcileProcessingAppointmentPaymentsJob < ApplicationJob
  queue_as :default

  def perform
    Payment
      .where(status: "processing", provider: "stripe")
      .where.not(appointment_id: nil, provider_payment_id: nil)
      .where("updated_at <= ?", 15.minutes.ago)
      .find_each do |payment|
        reconcile(payment)
      end
  end

  private

  def reconcile(payment)
    lock_key = Zlib.crc32("appointment-payment-reconciliation:#{payment.id}")

    ActiveRecord::Base.connection_pool.with_connection do |connection|
      acquired = connection.select_value(
        "SELECT pg_try_advisory_lock(#{lock_key})"
      )

      return unless acquired == true || acquired == "t"

      begin
        payment.reload

        return unless payment.status == "processing"
        return if payment.updated_at > 15.minutes.ago

        payment_intent = Stripe::PaymentIntent.retrieve(
          payment.provider_payment_id
        )

        if payment_intent.status == "succeeded"
          Payments::HandleSucceeded.new(
            payment_intent: payment_intent
          ).call
        end

        payment.reload
        payment.touch if payment.status == "processing"
      ensure
        connection.select_value(
          "SELECT pg_advisory_unlock(#{lock_key})"
        )
      end
    end
  rescue StandardError => error
    Rails.logger.error(
      "Failed to reconcile appointment payment " \
      "#{payment.id}: #{error.class}: #{error.message}"
    )
  end
end
