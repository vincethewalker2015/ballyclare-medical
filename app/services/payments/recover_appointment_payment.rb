
require "zlib"

module Payments
  class RecoverAppointmentPayment
    class PaymentNotRecoverable < StandardError; end

    MAX_RECOVERY_AGE = 12.hours

    def initialize(payment:)
      @payment = payment
    end

    def call
      raise PaymentNotRecoverable unless payment.appointment_id.present?

      # Keep the advisory lock on one PostgreSQL connection
      # throughout the entire recovery operation.
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        lock_key = Zlib.crc32("payment-recovery:#{payment.id}")

        acquired = connection.select_value(
          "SELECT pg_try_advisory_lock(#{lock_key})"
        )

        unless acquired == true || acquired == "t"
          raise PaymentNotRecoverable,
                "Another recovery attempt is already in progress"
        end

        begin
          recover_payment
        ensure
          connection.select_value(
            "SELECT pg_advisory_unlock(#{lock_key})"
          )
        end
      end
    end

    private

    attr_reader :payment

    def recover_payment
      appointment = Appointment.find(payment.appointment_id)

      appointment.with_lock do
        payment.with_lock do
          validate_payment!
        end
      end

      # Reuse the original Stripe request and idempotency key.
      # No appointment or payment row locks are held here.
      payment_intent =
        begin
          PaymentProviders::StripeProvider::CreatePayment.new(
            payment: payment
          ).call
        rescue RuntimeError => error
          if error.message == "Payment is associated with a different Stripe PaymentIntent"
            raise PaymentNotRecoverable,
                  "Payment changed while Stripe recovery was in progress"
          end

          raise
        end

      appointment.with_lock do
        payment.with_lock do
          unless payment.provider_payment_id == payment_intent.id
            raise PaymentNotRecoverable,
                  "PaymentIntent changed during recovery"
          end

          unless payment.status == "processing"
            raise PaymentNotRecoverable,
                  "Payment is no longer awaiting completion"
          end
        end
      end

      payment_intent
    end

    def validate_payment!
      if appointment_cancelled?
        raise PaymentNotRecoverable,
              "Cannot recover payment for a cancelled appointment"
      end

      unless payment.provider == "stripe" &&
             payment.status == "pending" &&
             payment.provider_payment_id.blank? &&
             payment.idempotency_key.present?
        raise PaymentNotRecoverable,
              "Payment is not eligible for recovery"
      end

      if payment.created_at < MAX_RECOVERY_AGE.ago
        raise PaymentNotRecoverable,
              "Payment is too old for safe automatic recovery"
      end
    end

    def appointment_cancelled?
      Appointment.find(payment.appointment_id).status == "cancelled"
    end
  end
end
