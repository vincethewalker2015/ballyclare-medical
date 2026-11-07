module Consultations
  class Resume
    class InvalidState < StandardError; end
    class Unauthorized < StandardError; end

    def initialize(appointment:, clinician:, user:)
      @appointment, @clinician, @user = appointment, clinician, user
    end

    def call
      @appointment.with_lock do
        authorize!
        return @appointment if @appointment.status == "in_consultation" && @appointment.encounter.present?

        encounter = @appointment.encounter
        unless @appointment.status == "consultation_interrupted" && encounter &&
            encounter.practice_id == @appointment.practice_id &&
            encounter.patient_id == @appointment.patient_id &&
            encounter.clinician_id == @clinician.id &&
            encounter.ended_at.nil? &&
            !encounter.clinical_notes.exists?(status: "signed")
          raise InvalidState, "Only an unfinished consultation can be resumed"
        end

        @appointment.update!(status: "in_consultation")
        @appointment.appointment_status_changes.create!(
          from_status: "consultation_interrupted", to_status: "in_consultation", changed_by: @user
        )
        AuditEvent.create!(
          practice: @appointment.practice, user: @user, auditable: encounter,
          action: "clinical.consultation_resumed",
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