module Booking
  class CreateStaffAppointment
    class SlotUnavailable < StandardError; end
    class PracticeMismatch < StandardError; end

    def initialize(
      appointment_slot:,
      patient:,
      booked_by:,
      reason: nil
    )
      @appointment_slot = appointment_slot
      @patient = patient
      @booked_by = booked_by
      @reason = reason
    end

    def call
      appointment = AppointmentSlot.transaction do
        StaffMember.lock.find(appointment_slot.clinician_id)

        appointment_slot.with_lock do
          ensure_patient_belongs_to_practice!
          ensure_slot_is_available!

          appointment = create_appointment!
          create_initial_charge!(appointment)

          appointment
        end
      end

      # The appointment and charge are committed above. A failure in the
      # optional live diary refresh must not turn a successful booking into
      # an HTTP 500 (which could prompt staff to book the slot again).
      begin
        Turbo::StreamsChannel.broadcast_action_to(
          [ appointment.practice, :appointments ],
          action: :refresh,
          target: "appointment_diary_list"
        )
      rescue StandardError => error
        Rails.logger.error(
          "Appointment #{appointment.id} saved, but diary broadcast failed: " \
          "#{error.class}: #{error.message}"
        )
      end

      appointment
    end

    private

    attr_reader :appointment_slot,
                :patient,
                :booked_by,
                :reason

    def create_appointment!
      Appointment.create!(
        practice: appointment_slot.practice,
        appointment_slot: appointment_slot,
        patient: patient,
        clinician: appointment_slot.clinician,
        reason: reason,
        status: "booked",
        booked_at: Time.current
      )
    end

    def create_initial_charge!(appointment)
      Billing::CreateCharge.new(
        appointment: appointment,
        description: reason.presence || "Appointment",
        charge_type: "appointment",
        amount_cents: Billing::ConsultationPrice.new(practice: appointment.practice, clinician: appointment.clinician).call.amount_cents,
        created_by: booked_by
      ).call
    end

    def ensure_patient_belongs_to_practice!
      return if patient.practice_id == appointment_slot.practice_id

      raise PracticeMismatch,
            "Patient and appointment slot must belong to the same practice"
    end

    def ensure_slot_is_available!
      unless appointment_slot.clinician.active? && appointment_slot.availability_block.active?
        raise SlotUnavailable,
              "Appointment slot is no longer available"
      end

      if appointment_slot.starts_at <= Time.current
        raise SlotUnavailable,
              "Appointment slot is no longer in the future"
      end

      if Appointment.where(appointment_slot_id: appointment_slot.id)
                    .where.not(status: "cancelled")
                    .exists?
        raise SlotUnavailable,
              "Appointment slot has already been booked"
      end

      if AppointmentHold.active.exists?(
        appointment_slot_id: appointment_slot.id
      )
        raise SlotUnavailable,
              "Appointment slot is currently being held"
      end
    end
  end
end
