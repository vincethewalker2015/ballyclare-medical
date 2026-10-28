module GuestBookings
  class CompleteEmergencyUnpaidBooking
    Unavailable = Class.new(StandardError)

    def initialize(hold:)
      @hold = hold
    end

    def call
      AppointmentHold.transaction do
        slot = hold.appointment_slot
        StaffMember.lock.find(slot.clinician_id)

        slot.with_lock do
          hold.lock!
          guest = hold.guest_booking
          raise Unavailable, "A guest reservation is required" unless guest

          guest.lock!
          raise Unavailable, "The reservation has expired" if hold.expired?
          raise Unavailable, "The guest booking has expired" if guest.expires_at <= Time.current
          raise Unavailable, "The guest booking is not awaiting payment" unless guest.status == "payment_pending"
          raise Unavailable, "Practice or clinician mismatch" unless GuestBookings::PracticeConsistency.valid?(guest: guest, slot: slot)
          raise Unavailable, "Online booking is unavailable" unless slot.availability_block.reload.active? && slot.availability_block.bookable_online?
          raise Unavailable, "Clinician is unavailable" unless slot.clinician.active?
          raise Unavailable, "The slot is in the past" unless slot.starts_at > Time.current
          raise Unavailable, "The slot is already booked" if slot.appointments.where.not(status: "cancelled").exists?

          policy = Payments::EmergencyUnpaidBookingPolicy.new(
            practice: slot.practice, payment: hold.payments.first || guest.payment
          )
          raise Unavailable, "Emergency unpaid booking is not permitted" unless policy.allowed?

          fee = Billing::ConsultationPrice.new(practice: slot.practice, clinician: slot.clinician).call

          patient = Patient.create!(
            practice: guest.practice,
            patient_type: "external",
            first_name: guest.first_name,
            last_name: guest.last_name,
            date_of_birth: guest.date_of_birth,
            email: guest.email,
            phone: guest.phone
          )

          appointment = Appointment.create!(
            practice: slot.practice,
            appointment_slot: slot,
            patient: patient,
            clinician: slot.clinician,
            status: "booked",
            reason: guest.consultation_reason,
            booked_at: Time.current
          )

          Billing::CreateCharge.new(
            appointment: appointment,
            description: "Appointment",
            charge_type: "appointment",
            amount_cents: fee.amount_cents
          ).call

          guest.update!(patient: patient, status: "completed")
          guest.update!(GuestBookings::ClearCompletedDetails::SENSITIVE_ATTRIBUTES.index_with { nil })
          hold.destroy!
          appointment
        end
      end
    end

    private

    attr_reader :hold
  end
end
