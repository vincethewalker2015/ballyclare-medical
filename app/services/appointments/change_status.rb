module Appointments
  class ChangeStatus
    class InvalidTransition < StandardError; end

    TRANSITIONS = {
      "booked" => %w[confirmed cancelled],
      "confirmed" => %w[arrived cancelled did_not_attend],
      "arrived" => %w[in_consultation cancelled],
      "in_consultation" => %w[completed referred],
      "completed" => [],
      "cancelled" => [],
      "referred" => [],
      "did_not_attend" => []
    }.freeze

    def self.allowed_transitions(status)
      TRANSITIONS.fetch(status.to_s, [])
    end

    def initialize(appointment:, to_status:, changed_by:)
      @appointment = appointment
      @to_status = to_status.to_s
      @changed_by = changed_by
    end

    def call
      appointment.with_lock do
        validate_transition!

        from_status = appointment.status

        Appointment.transaction do
          appointment.update!(status: to_status)

          appointment.appointment_status_changes.create!(
            from_status: from_status,
            to_status: to_status,
            changed_by: changed_by
          )

          if to_status == "cancelled" &&
            !appointment.payments.where(status: "succeeded").exists?
            appointment.appointment_charges
                      .active
                      .update_all(status: "voided")
          end
        end
      end

      appointment
    end

    private

    attr_reader :appointment, :to_status, :changed_by

    def validate_transition!
      allowed = TRANSITIONS.fetch(appointment.status, [])

      return if allowed.include?(to_status)

      raise InvalidTransition,
            "Cannot change appointment from #{appointment.status} to #{to_status}"
    end
  end
end
