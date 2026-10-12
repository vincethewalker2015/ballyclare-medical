
module Payments
  class ReconcileAppointmentPayment
    class PaymentNotReconciliable < StandardError; end

    def initialize(payment:)
      @payment = payment
    end

    def call
      unless payment.appointment_id.present? &&
             payment.provider == "stripe" &&
             payment.provider_payment_id.present?
        raise PaymentNotReconciliable,
              "Payment cannot be reconciled with Stripe"
      end

      appointment = Appointment.find(payment.appointment_id)
      payment_intent_id = payment.provider_payment_id

      # Retrieve Stripe's current status outside database locks.
      payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)

      appointment.with_lock do
        payment.with_lock do
          unless payment.provider_payment_id == payment_intent_id &&
                 payment_intent.id == payment_intent_id
            raise PaymentNotReconciliable,
                  "Stripe PaymentIntent does not match the payment"
          end

          unless %w[pending processing].include?(payment.status)
            raise PaymentNotReconciliable,
                  "Payment is no longer awaiting completion"
          end

          unless payment_intent.status == "canceled"
            raise PaymentNotReconciliable,
                  "Stripe has not confirmed cancellation"
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
