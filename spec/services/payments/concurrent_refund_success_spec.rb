require "rails_helper"
require "timeout"

RSpec.describe "Concurrent Stripe refund success callbacks", :concurrency do
  self.use_transactional_tests = false

  it "records one successful refund and preserves its first completion timestamp" do
    payment = create(:payment, status: "succeeded", amount_cents: 5000,
      currency: "GBP", paid_at: Time.current)
    refund = create(:refund, payment: payment, amount_cents: 2000,
      currency: "GBP", status: "processing",
      provider_refund_id: "re_concurrent_success", refunded_at: nil)
    stripe_refund = Stripe::Refund.construct_from(
      id: "re_concurrent_success", object: "refund",
      amount: 2000, currency: "gbp", status: "succeeded"
    )

    first_locked = Queue.new
    release_first = Queue.new
    second_pid = Queue.new
    first = nil
    second = nil

    begin
      first = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Refund.transaction do
            Refund.lock.find(refund.id)
            first_locked << true
            release_first.pop
            Payments::HandleRefundSucceeded.new(stripe_refund: stripe_refund).call
          end
        end
      end
      Timeout.timeout(10) { first_locked.pop }

      second = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          second_pid << connection.select_value("SELECT pg_backend_pid()")
          Payments::HandleRefundSucceeded.new(stripe_refund: stripe_refund).call
        end
      end
      pid = Timeout.timeout(10) { second_pid.pop }

      Timeout.timeout(10) do
        loop do
          blocked = ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.select_value(ActiveRecord::Base.sanitize_sql_array([
              "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = ? AND datname = current_database() AND wait_event_type = 'Lock')",
              pid
            ]))
          end
          break if blocked == true || blocked == "t"
          Thread.pass
        end
      end
      expect(second.join(0)).to be_nil

      release_first << true
      Timeout.timeout(10) { first.value }
      first_completed_at = refund.reload.refunded_at
      expect(first_completed_at).to be_present
      Timeout.timeout(10) { second.value }

      expect(refund.reload.status).to eq("succeeded")
      expect(refund.provider_refund_id).to eq("re_concurrent_success")
      expect(refund.refunded_at).to eq(first_completed_at)
      expect(Refund.where(payment_id: payment.id).count).to eq(1)
      expect(Refund.where(payment_id: payment.id, status: "succeeded").sum(:amount_cents)).to eq(2000)
    ensure
      release_first << true
      [ first, second ].compact.each { |thread| thread.join(10) }
    end
  end
end
