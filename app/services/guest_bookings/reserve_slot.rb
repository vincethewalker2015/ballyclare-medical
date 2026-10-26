module GuestBookings
  class ReserveSlot
    class Unavailable < StandardError; end

    def initialize(guest_booking:)
      @guest_booking = guest_booking
    end

    def call
      AppointmentSlot.transaction do
        slot = guest_booking.appointment_slot
        StaffMember.lock.find(slot.clinician_id)

        slot.with_lock do
          guest_booking.lock!
          raise Unavailable, "Guest booking has expired" if guest_booking.expires_at <= Time.current
          raise Unavailable, "Guest booking is not a draft" unless guest_booking.status == "draft"
          raise Unavailable, "Online booking is no longer available" unless slot.availability_block.active? && slot.availability_block.bookable_online?
          raise Unavailable, "Clinician is unavailable" unless slot.clinician.active?
          raise Unavailable, "Slot is in the past" unless slot.starts_at > Time.current
          raise Unavailable, "Slot is already booked" if slot.appointments.where.not(status: "cancelled").exists?
          raise Unavailable, "Slot is already reserved" if slot.appointment_holds.active.exists?

          hold = slot.appointment_holds.create!(
            guest_booking: guest_booking,
            expires_at: AppointmentSlot::HOLD_DURATION.from_now
          )
          guest_booking.update!(status: "payment_pending", expires_at: hold.expires_at)
          hold
        end
      end
    end

    private

    attr_reader :guest_booking
  end
end
