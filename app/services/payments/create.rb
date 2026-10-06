module Payments
  class Create
    class HoldExpired < StandardError; end
    class PracticeMismatch < StandardError; end

    def initialize(hold:, amount_cents:, currency:, provider:)
      @hold = hold
      @amount_cents = amount_cents
      @currency = currency
      @provider = provider
    end

    def call
      raise HoldExpired, "Appointment hold has expired" if hold.expired?

      unless currency == hold.appointment_slot.practice.currency
        raise PracticeMismatch,
              "Payment currency must match the practice currency"
      end

      Payment.create!(
        appointment_hold: hold,
        patient: hold.patient,
        provider: provider,
        amount_cents: amount_cents,
        currency: currency,
        status: "pending",
        idempotency_key: SecureRandom.uuid
      )
    end

    private

    attr_reader :hold, :amount_cents, :currency, :provider
  end
end
