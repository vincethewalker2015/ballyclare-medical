class RecoverPendingRefundsJob < ApplicationJob
  queue_as :default

  def perform
    Refund.where(status: "pending").find_each do |refund|
      begin
        ProcessRefundJob.perform_later(refund.id)
      rescue StandardError => error
        Rails.logger.error(
          "Failed to enqueue refund processing " \
          "for refund #{refund.id}: " \
          "#{error.class}: #{error.message}"
        )
      end
    end
  end
end
