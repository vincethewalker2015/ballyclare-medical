
module Payments
  class AbandonAppointmentPayment
    class PaymentNotAbandonable < StandardError; end

    def initialize(payment:)
      @payment = payment
    end

    def call
      raise PaymentNotAbandonable unless payment.appointment_id.present?

      appointment = Appointment.find(payment.appointment_id)

      validated_payment_intent_id = nil

      appointment.with_lock do
        if appointment.status == "cancelled"
          raise PaymentNotAbandonable,
                "Cannot abandon a payment for a cancelled appointment"
        end

        payment.with_lock do
          unless %w[pending processing].include?(payment.status)
            raise PaymentNotAbandonable,
                  "Payment is no longer awaiting completion"
          end

          unless payment.provider == "stripe"
            raise PaymentNotAbandonable,
                  "Payment does not belong to Stripe"
          end

          if payment.provider_payment_id.blank?
            raise PaymentNotAbandonable,
                  "Payment has no known Stripe PaymentIntent ID"
          end

          validated_payment_intent_id = payment.provider_payment_id
        end
      end

      # Stripe API call happens outside database locks.
      payment_intent =
        PaymentProviders::StripeProvider::CancelPayment.new(
          payment: payment,
          payment_intent_id: validated_payment_intent_id
        ).call

      appointment.with_lock do
        if appointment.status == "cancelled"
          raise PaymentNotAbandonable,
                "Appointment was cancelled during payment abandonment"
        end

        payment.with_lock do
          unless %w[pending processing].include?(payment.status)
            raise PaymentNotAbandonable,
                  "Payment is no longer awaiting completion"
          end

          unless payment.provider_payment_id == validated_payment_intent_id &&
                 payment_intent.id == validated_payment_intent_id
            raise PaymentNotAbandonable,
                  "Stripe PaymentIntent does not match the validated payment"
          end

          unless payment_intent.status == "canceled"
            raise PaymentNotAbandonable,
                  "Stripe cancellation was not confirmed"
          end

          payment.update!(status: "cancelled")
        end
      end

      payment
    end

    private

    attr_reader :payment
  end
end
