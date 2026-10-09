module Booking
  class CreateStaffAppointment
    class SlotUnavailable < StandardError; end
    class PracticeMismatch < StandardError; end

    def initialize(
      appointment_slot:,
      patient:,
      booked_by:,
      reason: nil,
      amount_cents:
    )
      @appointment_slot = appointment_slot
      @patient = patient
      @booked_by = booked_by
      @reason = reason
      @amount_cents = amount_cents
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

      Turbo::StreamsChannel.broadcast_action_to(
        [ appointment.practice, :appointments ],
        action: :refresh,
        target: "appointment_diary_list"
      )

      appointment
    end

    private

    attr_reader :appointment_slot,
                :patient,
                :booked_by,
                :reason,
                :amount_cents

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
        amount_cents: amount_cents,
        created_by: booked_by
      ).call
    end

    def ensure_patient_belongs_to_practice!
      return if patient.practice_id == appointment_slot.practice_id

      raise PracticeMismatch,
            "Patient and appointment slot must belong to the same practice"
    end

    def ensure_slot_is_available!
      unless appointment_slot.availability_block.active?
        raise SlotUnavailable,
              "Appointment slot is no longer available"
      end

      if Appointment.exists?(
        appointment_slot_id: appointment_slot.id
      )
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
