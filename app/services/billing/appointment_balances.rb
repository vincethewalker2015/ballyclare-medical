module Billing
  class AppointmentBalances
    def initialize(appointments:)
      @appointments = appointments
    end

    def call
      appointment_ids.index_with do |appointment_id|
        {
          charged_cents: charged_cents.fetch(appointment_id, 0),
          paid_cents: paid_cents.fetch(appointment_id, 0),
          refunded_cents: refunded_cents.fetch(appointment_id, 0),
          balance_cents: balance_cents_for(appointment_id),
          currency: currency_for(appointment_id)
        }
      end
    end

    private

    attr_reader :appointments

    def appointment_ids
      @appointment_ids ||= appointments.map(&:id)
    end

    def charged_cents
      @charged_cents ||= AppointmentCharge
        .where(
          appointment_id: appointment_ids,
          status: "active"
        )
        .group(:appointment_id)
        .sum(:amount_cents)
    end

    def paid_cents
      @paid_cents ||= Payment
        .where(
          appointment_id: appointment_ids,
          status: "succeeded"
        )
        .group(:appointment_id)
        .sum(:amount_cents)
    end

    def refunded_cents
      @refunded_cents ||= Refund
        .joins(:payment)
        .where(
          payments: {
            appointment_id: appointment_ids
          },
          refunds: {
            status: "succeeded"
          }
        )
        .group("payments.appointment_id")
        .sum(:amount_cents)
    end

    def balance_cents_for(appointment_id)
      charged_cents.fetch(appointment_id, 0) -
        paid_cents.fetch(appointment_id, 0) +
        refunded_cents.fetch(appointment_id, 0)
    end

    def currency_for(appointment_id)
      appointments_by_id
        .fetch(appointment_id)
        .practice
        .currency
    end

    def appointments_by_id
      @appointments_by_id ||= appointments.index_by(&:id)
    end
  end
end
