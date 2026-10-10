
module Payments
  class HandleFailed
    class PaymentNotFound < StandardError; end
    class AmountMismatch < StandardError; end
    class CurrencyMismatch < StandardError; end

    def initialize(payment_intent:)
      @payment_intent = payment_intent
    end

    def call
      payment = find_payment!

      if payment.appointment_id.present?
        appointment = Appointment.find(payment.appointment_id)

        appointment.with_lock do
          process_payment!(payment)
        end
      else
        process_payment!(payment)
      end
    end

    private

    attr_reader :payment_intent

    def find_payment!
      payment = Payment.find_by(
        provider: "stripe",
        provider_payment_id: payment_intent.id
      )

      return payment if payment

      payment_id = payment_intent.metadata&.[]("payment_id")

      if payment_id.present?
        payment = Payment.find_by(
          id: payment_id,
          provider: "stripe"
        )

        return payment if payment
      end

      raise PaymentNotFound,
            "Payment not found for Stripe PaymentIntent #{payment_intent.id}"
    end

    def validate_amount!(payment)
      return if payment.amount_cents == payment_intent.amount

      raise AmountMismatch,
            "Stripe payment amount does not match local payment"
    end

    def validate_currency!(payment)
      return if payment.currency.casecmp?(payment_intent.currency)

      raise CurrencyMismatch,
            "Stripe payment currency does not match local payment"
    end

    def process_payment!(payment)
      payment.with_lock do
        validate_amount!(payment)
        validate_currency!(payment)
        if payment.provider_payment_id.present? &&
           payment.provider_payment_id != payment_intent.id
          raise PaymentNotFound,
                "Payment is associated with a different Stripe PaymentIntent"
        end

        return payment if payment.status == "succeeded"
        return payment if payment.status == "requires_refund"
        return payment if payment.status == "failed"

        if payment.provider_payment_id.nil?
          payment.update!(
            provider_payment_id: payment_intent.id
          )
        end

        if payment.appointment_id.present? &&
           payment_intent.status != "canceled"
          payment.update!(status: "processing")
        else
          payment.update!(status: "failed")
        end
      end

      payment
    end
  end
end
