module Consultations
  class SignAndComplete
    class InvalidState < StandardError; end
    class Conflict < StandardError; end
    class Unauthorized < StandardError; end

    def initialize(appointment:, clinician:, user:, lock_version:)
      @appointment, @clinician, @user, @lock_version = appointment, clinician, user, lock_version
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

        raise InvalidState, "Consultation is not in progress" unless appointment.status == "in_consultation"
        encounter = appointment.encounter
        raise InvalidState, "Encounter is missing" unless encounter && encounter.practice_id == appointment.practice_id
        note = encounter.clinical_notes.find_by(note_type: "consultation", status: "draft")
        raise InvalidState, "Save a draft before signing" unless note
        raise InvalidState, "Clinical note cannot be blank" if note.body.blank?
        raise Conflict unless note.lock_version.to_s == @lock_version.to_s

        signed_at = Time.current
        note.update!(status: "signed", signed_at: signed_at)
        encounter.update!(ended_at: signed_at)
        appointment.update!(status: "completed", completed_at: signed_at)
        appointment.appointment_status_changes.create!(
          from_status: "in_consultation", to_status: "completed", changed_by: user
        )
        AuditEvent.create!(
          practice: appointment.practice, user: user, auditable: note,
          action: "clinical.note_signed",
          metadata: { appointment_id: appointment.id, staff_member_id: clinician.id }
        )
        AuditEvent.create!(
          practice: appointment.practice, user: user, auditable: encounter,
          action: "clinical.consultation_completed",
          metadata: { appointment_id: appointment.id, staff_member_id: clinician.id }
        )
        note
      end
    rescue ActiveRecord::StaleObjectError
      raise Conflict
    end

    private

    attr_reader :appointment, :clinician, :user
  end
end
