module Consultations
  class Start
    class InvalidState < StandardError; end
    class Unauthorized < StandardError; end

    def initialize(appointment:, clinician:, user:)
      @appointment = appointment
      @clinician = clinician
      @user = user
    end

    def call
      appointment.with_lock do
        unless clinician.active? && clinician.access_level == "staff_clinician" &&
            clinician.staff_type.in?(%w[doctor nurse]) &&
            clinician.practice_id == appointment.practice_id &&
            clinician.id == appointment.clinician_id &&
            clinician.user_id == user.id
          raise Unauthorized, "Only the assigned active clinician may start this consultation"
        end

        existing = appointment.encounter
        return existing if existing && appointment.status == "in_consultation"

        unless appointment.status.in?(%w[arrived in_consultation]) && existing.nil?
          raise InvalidState, "The patient must be marked arrived before starting a consultation"
        end

        # Repair legacy appointments marked in consultation through the old
        # generic status endpoint without creating a clinical encounter.
        # Only the assigned clinician may perform this repair.

        started_at = Time.current
        encounter = Encounter.create!(
          appointment: appointment,
          practice: appointment.practice,
          patient: appointment.patient,
          clinician: clinician,
          encounter_type: "consultation",
          started_at: started_at
        )

        if appointment.status == "arrived"
          appointment.update!(status: "in_consultation", consultation_started_at: started_at)
          appointment.appointment_status_changes.create!(
            from_status: "arrived",
            to_status: "in_consultation",
            changed_by: user
          )
        else
          appointment.update!(consultation_started_at: started_at) if appointment.consultation_started_at.nil?
        end
        AuditEvent.create!(
          practice: appointment.practice,
          user: user,
          auditable: encounter,
          action: "clinical.consultation_started",
          metadata: { appointment_id: appointment.id, staff_member_id: clinician.id }
        )
        encounter
      end
    end

    private

    attr_reader :appointment, :clinician, :user
  end
end
