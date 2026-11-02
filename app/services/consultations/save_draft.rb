module Consultations
  class SaveDraft
    class InvalidState < StandardError; end
    class Unauthorized < StandardError; end
    class Conflict < StandardError; end

    def initialize(appointment:, clinician:, user:, body:, lock_version:)
      @appointment, @clinician, @user = appointment, clinician, user
      @body, @lock_version = body, lock_version
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
        raise InvalidState unless appointment.status == "in_consultation"
        encounter = appointment.encounter
        raise InvalidState unless encounter && encounter.practice_id == appointment.practice_id

        note = encounter.clinical_notes.find_by(note_type: "consultation", status: "draft")
        if note
          raise Conflict unless @lock_version.to_s == note.lock_version.to_s
          note.update!(body: @body)
          action = "clinical.draft_updated"
        else
          raise Conflict unless @lock_version.to_s == "0"
          note = encounter.clinical_notes.create!(
            patient: appointment.patient, author: clinician,
            note_type: "consultation", status: "draft", body: @body
          )
          action = "clinical.draft_created"
        end
        AuditEvent.create!(
          practice: appointment.practice, user: user, auditable: note,
          action: action,
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
