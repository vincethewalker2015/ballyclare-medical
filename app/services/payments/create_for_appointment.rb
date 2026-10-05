# In the case where a staff member books an appointment for a patient and takes a payment from them
#
module Payments
  class CreateForAppointment
    class AmountExceedsBalance < StandardError; end
    class PaymentInProgress < StandardError; end

    def initialize(
      appointment:,
      amount_cents:
    )
      @appointment = appointment
      @amount_cents = amount_cents
    end

    def call
      Appointment.transaction do
        appointment.with_lock do
          ensure_no_payment_in_progress!
          ensure_amount_does_not_exceed_balance!

          create_payment!
        end
      end
    end

    private

      attr_reader :appointment,
                  :amount_cents

    def create_payment!
      Payment.create!(
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        amount_cents: amount_cents,
        currency: appointment.practice.currency,
        status: "pending",
        idempotency_key: SecureRandom.uuid
      )
    end

    def ensure_no_payment_in_progress!
      return unless appointment.payments.where(
        status: %w[pending processing]
      ).exists?

      raise PaymentInProgress,
            "Another payment is already in progress"
    end

    def ensure_amount_does_not_exceed_balance!
      balance = Billing::AppointmentBalance.new(
        appointment: appointment
      ).call

      return if amount_cents <= balance[:balance_cents]

      raise AmountExceedsBalance,
            "Payment amount exceeds the outstanding balance"
    end
  end
end
