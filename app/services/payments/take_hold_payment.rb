module Payments
  class TakeHoldPayment
    Result = Data.define(:payment, :payment_intent)

    def initialize(hold:)
      @hold = hold
    end

    def call
      payment = Payments::CreateForHold.new(hold: @hold).call
      intent = PaymentProviders::StripeProvider::CreatePayment.new(payment: payment).call
      Result.new(payment: payment, payment_intent: intent)
    rescue Stripe::StripeError
      # Stripe may have created the intent before the response failed.
      # Retain the Payment and idempotency key so retries are safe.
      raise
    end
  end
end
