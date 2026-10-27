class RecoverPaidGuestBookingsJob < ApplicationJob
  queue_as :default

  def perform
    Payment.where(provider: "stripe", status: "succeeded", appointment_id: nil)
      .where.not(guest_booking_id: nil)
      .where("updated_at < ?", 2.minutes.ago)
      .find_each do |payment|
        CompleteGuestBookingJob.perform_later(payment.id)
      end
  end
end
