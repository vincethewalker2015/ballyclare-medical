module Booking
  class CreateAppointment
    class HoldExpired < StandardError; end
    class SlotUnavailable < StandardError; end
    class InvalidHold < StandardError; end

    def initialize(hold:)
      @hold = hold
    end

    def call
      AppointmentSlot.transaction do
        StaffMember.lock.find(slot.clinician_id)

        slot.with_lock do
          hold.reload

          validate_hold!

          appointment = Appointment.create!(
            practice: slot.practice,
            appointment_slot: slot,
            patient: hold.patient,
            clinician: slot.clinician,
            status: "booked",
            booked_at: Time.current
          )

          hold.destroy!

          appointment
        end
      end
    end

    private

    attr_reader :hold

    def slot
      @slot ||= hold.appointment_slot
    end

    def validate_hold!
      raise HoldExpired, "Appointment hold has expired" if hold.expired?

      unless slot.availability_block.active?
        raise SlotUnavailable,
              "Appointment slot is no longer available"
      end

      if slot.starts_at <= Time.current
        raise SlotUnavailable, "Appointment slot is no longer in the future"
      end

      if Appointment.where(appointment_slot_id: slot.id)
                    .where.not(status: "cancelled")
                    .exists?
        raise SlotUnavailable, "Appointment slot has already been booked"
      end

      unless hold.appointment_slot_id == slot.id
        raise InvalidHold, "Hold does not belong to this appointment slot"
      end
    end
  end
end
