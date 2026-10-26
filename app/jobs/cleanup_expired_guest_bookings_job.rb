class CleanupExpiredGuestBookingsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100

  def perform
    GuestBooking.where(status: "draft")
      .where("expires_at <= ?", Time.current)
      .in_batches(of: BATCH_SIZE) do |batch|
        batch.delete_all
      end
  end
end
