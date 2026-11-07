module Consultations
  class AddAmendment
    class InvalidState < StandardError; end
    class Unauthorized < StandardError; end

    def initialize(appointment:, clinician:, user:, reason:, body:)
      @appointment, @clinician, @user = appointment, clinician, user
      @reason, @body = reason, body
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
        unless appointment.status == "completed" &&
            Appointment.where(id: appointment.id, status: "completed").exists? && encounter &&
            encounter.practice_id == appointment.practice_id &&
            encounter.patient_id == appointment.patient_id &&
            encounter.clinician_id == clinician.id
          raise InvalidState, "A completed consultation is required"
        end

        note = encounter.clinical_notes.find_by(note_type: "consultation", status: "signed")
        raise InvalidState, "A signed consultation note is required" unless note

        amendment = note.amendments.create!(author: clinician, reason: @reason, body: @body)
        AuditEvent.create!(
          practice: appointment.practice, user: user, auditable: amendment,
          action: "clinical.note_amended",
          metadata: { appointment_id: appointment.id, clinical_note_id: note.id, staff_member_id: clinician.id }
        )
        amendment
      end
    end

    private

    attr_reader :appointment, :clinician, :user
  end
end
