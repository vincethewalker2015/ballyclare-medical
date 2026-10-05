module Billing
  class AppointmentBalance
    def initialize(appointment:)
      @appointment = appointment
    end

    def call
      charged_cents = active_charged_cents
      paid_cents = successful_paid_cents
      refunded_cents = successful_refunded_cents

      {
        charged_cents: charged_cents,
        paid_cents: paid_cents,
        refunded_cents: refunded_cents,
        balance_cents: charged_cents - paid_cents + refunded_cents,
        currency: appointment.practice.currency
      }
    end

    private

      attr_reader :appointment

    def active_charged_cents
      appointment.appointment_charges
                 .active
                 .sum(:amount_cents)
    end

    def successful_paid_cents
      appointment.payments
                 .where(status: "succeeded")
                 .sum(:amount_cents)
    end

    def successful_refunded_cents
      Refund
        .joins(:payment)
        .where(
          payments: { appointment_id: appointment.id },
          refunds: { status: "succeeded" }
        )
        .sum(:amount_cents)
    end
  end
end
