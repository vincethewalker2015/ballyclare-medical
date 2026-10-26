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
          existing = hold.payments.order(:created_at).first
          if existing
            return existing if existing.status.in?(%w[pending processing])
            raise PaymentInProgress, "This reservation already has a completed or unsuccessful payment"
          end

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
