module Payments
  class HandleFailed
    class PaymentNotFound < StandardError; end

    def initialize(payment_intent:)
      @payment_intent = payment_intent
    end

    def call
      payment = find_payment!

      payment.with_lock do
        return payment if payment.status == "succeeded"
        return payment if payment.status == "requires_refund"

        payment.update!(
          status: "failed"
        )
      end

      payment
    end

    private

    attr_reader :payment_intent

    def find_payment!
      Payment.find_by(
        provider: "stripe",
        provider_payment_id: payment_intent.id
      ) || raise(
        PaymentNotFound,
        "Payment not found for Stripe PaymentIntent #{payment_intent.id}"
      )
    end
  end
end
