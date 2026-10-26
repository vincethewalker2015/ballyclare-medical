module PatientPortal
  class ReserveAppointment
    class NotApproved < StandardError; end
    class NotOnlineBookable < StandardError; end

    def initialize(patient_account:, appointment_slot_id:)
      @patient_account = patient_account
      @appointment_slot_id = appointment_slot_id
    end

    def call
      link = @patient_account.patient_account_links.approved.includes(:patient, :practice).first
      raise NotApproved, "An approved patient link is required" unless link && link.patient.practice_id == link.practice_id

      slot = link.practice.appointment_slots.includes(:availability_block, :clinician).find(@appointment_slot_id)
      unless slot.availability_block.practice_id == link.practice_id &&
             slot.availability_block.clinician_id == slot.clinician_id &&
             slot.availability_block.bookable_online? &&
             slot.clinician.practice_id == link.practice_id &&
             slot.clinician.staff_type.in?(%w[doctor nurse])
        raise NotOnlineBookable, "This appointment is not available for online booking"
      end

      slot.hold_for!(patient: link.patient)
    end
  end
end
