module Payments
  class HandleSucceeded
    class PaymentNotFound < StandardError; end
    class AmountMismatch < StandardError; end
    class CurrencyMismatch < StandardError; end

    def initialize(payment_intent:)
      @payment_intent = payment_intent
    end

    def call
      payment = Payment.find_by(
        provider: "stripe",
        provider_payment_id: payment_intent.id
      )

      raise PaymentNotFound,
            "Payment not found for Stripe PaymentIntent #{payment_intent.id}" unless payment

      payment.with_lock do
        validate_amount!(payment)
        validate_currency!(payment)

        return payment if payment.status == "succeeded"

        payment.update!(
          status: "succeeded",
          paid_at: Time.current
        )

        payment
      end
    end

    private

    attr_reader :payment_intent

    def validate_amount!(payment)
      return if payment.amount_cents == payment_intent.amount_received

      raise AmountMismatch,
            "Stripe payment amount does not match local payment"
    end

    def validate_currency!(payment)
      return if payment.currency.casecmp?(payment_intent.currency)

      raise CurrencyMismatch,
            "Stripe payment currency does not match local payment"
    end
  end
end
