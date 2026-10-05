module Payments
  class TakeAppointmentPayment
    def initialize(
      appointment:,
      amount_cents:
    )
      @appointment = appointment
      @amount_cents = amount_cents
    end

    Result = Data.define(:payment, :payment_intent)

    def call
      payment = Payments::CreateForAppointment.new(
        appointment: appointment,
        amount_cents: amount_cents
      ).call

      payment_intent =
        PaymentProviders::StripeProvider::CreatePayment.new(
          payment: payment
        ).call

      Result.new(
        payment: payment,
        payment_intent: payment_intent
      )
    rescue Stripe::StripeError
      payment&.update!(status: "failed")
      raise
    end

    private

      attr_reader :appointment,
                  :amount_cents
  end
end
