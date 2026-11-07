module Consultations
  class ReleaseDocument
    class InvalidState < StandardError; end
    class Unauthorized < StandardError; end

    def initialize(appointment:, clinician:, user:, title:, body:, printable: false)
      @appointment, @clinician, @user = appointment, clinician, user
      @title, @body, @printable = title, body, printable
    end

    def call
      appointment.with_lock do
        unless clinician.active? && clinician.access_level == "staff_clinician" &&
            clinician.staff_type.in?(%w[doctor nurse]) &&
            clinician.user_id == user.id &&
            clinician.id == appointment.clinician_id &&
            clinician.practice_id == appointment.practice_id
          raise Unauthorized
        end
        encounter = appointment.encounter
        unless appointment.status == "completed" && encounter &&
            encounter.practice_id == appointment.practice_id &&
            encounter.clinical_notes.exists?(note_type: "consultation", status: "signed")
          raise InvalidState, "A signed, completed consultation is required"
        end

        release = ClinicalDocumentRelease.create!(
          practice: appointment.practice, patient: appointment.patient,
          encounter: encounter, released_by: clinician,
          title: @title, body: @body, printable: ActiveModel::Type::Boolean.new.cast(@printable), released_at: Time.current
        )
        AuditEvent.create!(
          practice: appointment.practice, user: user, auditable: release,
          action: "clinical.document_released",
          metadata: { appointment_id: appointment.id, staff_member_id: clinician.id }
        )
        release
      end
    end

    private

    attr_reader :appointment, :clinician, :user
  end
end
