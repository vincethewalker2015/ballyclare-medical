module Payments
  class TakeAppointmentPayment
    def initialize(
      appointment:,
      amount_cents:
    )
      @appointment = appointment
      @amount_cents = amount_cents
    end

    def call
      payment = Payments::CreateForAppointment.new(
        appointment: appointment,
        amount_cents: amount_cents
      ).call

      begin
        PaymentProviders::StripeProvider::CreatePayment.new(
          payment: payment
        ).call
      rescue Stripe::StripeError
        payment.update!(status: "failed")
        raise
      end

      payment
    end

    private

    attr_reader :appointment,
                :amount_cents
  end
end
