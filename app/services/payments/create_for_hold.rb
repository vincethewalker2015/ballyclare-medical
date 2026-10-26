module Payments
  class CreateForHold
    class HoldExpired < StandardError; end
    class PaymentInProgress < StandardError; end

    def initialize(hold:)
      @hold = hold
    end

    def call
      AppointmentHold.transaction do
        hold.with_lock do
          raise HoldExpired, "Reservation has expired" if hold.expired?
          raise PaymentInProgress, "Payment already started for this reservation" if hold.payments.exists?

          slot = hold.appointment_slot
          fee = Billing::ConsultationPrice.new(practice: slot.practice, clinician: slot.clinician).call

          Payment.create!(
            appointment_hold: hold,
            patient: hold.patient,
            provider: "stripe",
            currency: fee.currency,
            amount_cents: fee.amount_cents,
            status: "pending",
            idempotency_key: SecureRandom.uuid
          )
        end
      end
    end

    private

    attr_reader :hold
  end
end
