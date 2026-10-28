module PatientPortal
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
          patient = hold.patient
          raise Unavailable, "A patient reservation is required" unless patient
          raise Unavailable, "The reservation has expired" if hold.expired?
          raise Unavailable, "Patient or clinician practice mismatch" unless patient.practice_id == slot.practice_id && slot.clinician.practice_id == slot.practice_id
          raise Unavailable, "Online booking is unavailable" unless slot.availability_block.reload.active? && slot.availability_block.bookable_online?
          raise Unavailable, "Clinician is unavailable" unless slot.clinician.active?
          raise Unavailable, "The slot is in the past" unless slot.starts_at > Time.current
          raise Unavailable, "The slot is already booked" if slot.appointments.where.not(status: "cancelled").exists?

          policy = Payments::EmergencyUnpaidBookingPolicy.new(
            practice: slot.practice, payment: hold.payments.first
          )
          raise Unavailable, "Emergency unpaid booking is not permitted" unless policy.allowed?

          fee = Billing::ConsultationPrice.new(practice: slot.practice, clinician: slot.clinician).call
          appointment = Appointment.create!(
            practice: slot.practice, appointment_slot: slot, patient: patient,
            clinician: slot.clinician, status: "booked", booked_at: Time.current
          )

          Billing::CreateCharge.new(
            appointment: appointment, description: "Appointment",
            charge_type: "appointment", amount_cents: fee.amount_cents
          ).call

          hold.destroy!
          appointment
        end
      end
    end

    private

    attr_reader :hold
  end
end
