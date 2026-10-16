require "zlib"

class ProcessRefundJob < ApplicationJob
  queue_as :default

  def perform(refund_id)
    lock_key = Zlib.crc32("refund-processing:#{refund_id}")

    ActiveRecord::Base.connection_pool.with_connection do |connection|
      lock_acquired = connection.select_value(
        "SELECT pg_try_advisory_lock(#{lock_key})"
      )

      return unless lock_acquired

      begin
        refund = Refund.find(refund_id)

        return unless refund.status == "pending"

        PaymentProviders::StripeProvider::CreateRefund.new(
          refund: refund
        ).call
      ensure
        connection.select_value(
          "SELECT pg_advisory_unlock(#{lock_key})"
        )
      end
    end
  end
end
