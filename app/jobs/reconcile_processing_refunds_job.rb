require "zlib"

class ReconcileProcessingRefundsJob < ApplicationJob
  queue_as :default

  def perform
    Refund
      .where(status: "processing")
      .where("updated_at <= ?", 15.minutes.ago)
      .find_each do |refund|
        reconcile(refund)
      end
  end

  private

  def reconcile(refund)
    lock_key = Zlib.crc32("refund-reconciliation:#{refund.id}")

    ActiveRecord::Base.connection_pool.with_connection do |connection|
      lock_acquired = connection.select_value(
        "SELECT pg_try_advisory_lock(#{lock_key})"
      )

      return unless lock_acquired

      begin
        # Another worker may have updated the refund while
        # this job was waiting to run.
        refund.reload

        return unless refund.status == "processing"
        return if refund.updated_at > 15.minutes.ago

        Payments::ReconcileRefund.new(
          refund: refund
        ).call

        refund.reload

        refund.touch if refund.status == "processing"
      ensure
        connection.select_value(
          "SELECT pg_advisory_unlock(#{lock_key})"
        )
      end
    end
  rescue StandardError => error
    Rails.logger.error(
      "Failed to reconcile refund " \
      "#{refund.id}: " \
      "#{error.class}: #{error.message}"
    )
  end
end
