module Billing
  class CreateCharge
    def initialize(
      appointment:,
      description:,
      charge_type:,
      amount_cents:,
      created_by: nil
    )
      @appointment = appointment
      @description = description
      @charge_type = charge_type
      @amount_cents = amount_cents
      @created_by = created_by
    end

    def call
      AppointmentCharge.create!(
        appointment: appointment,
        patient: appointment.patient,
        practice: appointment.practice,
        created_by: created_by,
        description: description,
        charge_type: charge_type,
        amount_cents: amount_cents,
        currency: appointment.practice.currency,
        status: "active",
        charged_at: Time.current
      )
    end

    private

    attr_reader :appointment,
                :description,
                :charge_type,
                :amount_cents,
                :created_by
  end
end
