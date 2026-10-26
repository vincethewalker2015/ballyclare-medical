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
    rescue Stripe::StripeError => error
      if payment && !error.is_a?(Stripe::APIConnectionError)
        payment.with_lock { payment.update!(status: "failed") }
      end
      raise
    end
  end
end
