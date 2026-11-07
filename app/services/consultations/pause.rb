module Consultations
  class Pause
    class InvalidState < StandardError; end
    class Unauthorized < StandardError; end

    def initialize(appointment:, clinician:, user:)
      @appointment, @clinician, @user = appointment, clinician, user
    end

    def call
      @appointment.with_lock do
        authorize!
        return @appointment if @appointment.status == "consultation_interrupted"

        encounter = @appointment.encounter
        unless @appointment.status == "in_consultation" && encounter &&
            encounter.practice_id == @appointment.practice_id &&
            encounter.patient_id == @appointment.patient_id &&
            encounter.clinician_id == @clinician.id &&
            encounter.ended_at.nil? &&
            !encounter.clinical_notes.exists?(status: "signed")
          raise InvalidState, "Only an active, unsigned consultation can be paused"
        end

        @appointment.update!(status: "consultation_interrupted")
        @appointment.appointment_status_changes.create!(
          from_status: "in_consultation", to_status: "consultation_interrupted", changed_by: @user
        )
        AuditEvent.create!(
          practice: @appointment.practice, user: @user, auditable: encounter,
          action: "clinical.consultation_paused",
          metadata: { appointment_id: @appointment.id, staff_member_id: @clinician.id }
        )
        @appointment
      end
    end

    private

    def authorize!
      unless @clinician.active? && @clinician.access_level == "staff_clinician" &&
          @clinician.staff_type.in?(%w[doctor nurse]) &&
          @clinician.user_id == @user.id &&
          @clinician.id == @appointment.clinician_id &&
          @clinician.practice_id == @appointment.practice_id
        raise Unauthorized
      end
    end
  end
end