module Booking
  class CreateHold
    HOLD_DURATION = 10.minutes

    class SlotUnavailable < StandardError; end

    def initialize(appointment_slot:, patient:)
      @appointment_slot = appointment_slot
      @patient = patient
    end

    def call
      AppointmentSlot.transaction do
        appointment_slot.with_lock do
          ensure_slot_available!

          AppointmentHold.create!(
            appointment_slot: appointment_slot,
            patient: patient,
            expires_at: HOLD_DURATION.from_now
          )
        end
      end
    end

    private

    attr_reader :appointment_slot, :patient

    def ensure_slot_available!
      if appointment_slot.appointment.present?
        raise SlotUnavailable, "Appointment slot has already been booked"
      end

      active_hold = appointment_slot.appointment_hold

      return unless active_hold

      if active_hold.expired?
        active_hold.destroy!
      else
        raise SlotUnavailable, "Appointment slot is currently being held"
      end
    end
  end
end
