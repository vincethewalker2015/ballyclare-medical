class CompleteGuestBookingJob < ApplicationJob
  queue_as :default
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5

  def perform(payment_id)
    payment = Payment.find(payment_id)
    return unless payment.guest_booking_id?

    Payment.transaction do
      payment.lock!
      return if payment.appointment_id.present? || payment.status == "requires_refund"
      return unless payment.status == "succeeded"

      guest = GuestBooking.lock.find(payment.guest_booking_id)
      unless guest.patient
        guest.update!(patient: Patient.create!(
          practice: guest.practice,
          patient_type: "external",
          first_name: guest.first_name,
          last_name: guest.last_name,
          date_of_birth: guest.date_of_birth,
          email: guest.email,
          phone: guest.phone
        ))
      end

      Payments::CompleteBooking.new(payment: payment).call
    end
  rescue Payments::CompleteBooking::HoldExpired,
         Payments::CompleteBooking::SlotUnavailable,
         Payments::CompleteBooking::MissingHold => error
    payment.with_lock do
      payment.update!(status: "requires_refund") if payment.status == "succeeded" && payment.appointment_id.nil?
    end
    Rails.logger.error("Paid guest booking requires refund: payment=#{payment_id} reason=#{error.class}")
  end
end
