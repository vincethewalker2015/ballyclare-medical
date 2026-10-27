module Payments
  class CompleteBooking
    class PaymentNotSucceeded < StandardError; end
    class MissingHold < StandardError; end
    class HoldExpired < StandardError; end
    class SlotUnavailable < StandardError; end

    def initialize(payment:)
      @payment = payment
    end

    def call
      Payment.transaction do
        payment.lock!

        return payment.appointment if payment.appointment.present?

        validate_payment!

        hold = payment.appointment_hold
        raise MissingHold, "Payment has no appointment hold" unless hold

        slot = hold.appointment_slot

        StaffMember.lock.find(slot.clinician_id)

        slot.with_lock do
          hold.reload

          raise HoldExpired, "Appointment hold has expired" if hold.expired?

          unless slot.availability_block.reload.active?
            raise SlotUnavailable,
                  "Appointment slot is no longer available"
          end

          if slot.starts_at <= Time.current
            raise SlotUnavailable,
                  "Appointment slot is no longer in the future"
          end

          if Appointment.where(appointment_slot_id: slot.id)
                        .where.not(status: "cancelled")
                        .exists?
            raise SlotUnavailable,
                  "Appointment slot has already been booked"
          end

          patient = hold.patient || hold.guest_booking&.patient
          raise MissingHold, "Booking patient is missing" unless patient

          appointment = Appointment.create!(
            practice: slot.practice,
            appointment_slot: slot,
            patient: patient,
            clinician: slot.clinician,
            status: "booked",
            reason: hold.guest_booking&.consultation_reason,
            booked_at: Time.current
          )

          Billing::CreateCharge.new(
            appointment: appointment,
            description: "Appointment",
            charge_type: "appointment",
            amount_cents: payment.amount_cents
          ).call

          payment.guest_booking&.update!(status: "completed")

          payment.update!(
            patient: patient,
            appointment: appointment,
            appointment_hold: nil
          )

          hold.destroy!

          if payment.guest_booking
            GuestBookings::ClearCompletedDetails.new(guest_booking: payment.guest_booking).call
          end

          appointment
        end
      end
    end

    private

    attr_reader :payment

    def validate_payment!
      return if payment.status == "succeeded"

      raise PaymentNotSucceeded,
            "Payment must have succeeded before booking can be completed"
    end
  end
end
