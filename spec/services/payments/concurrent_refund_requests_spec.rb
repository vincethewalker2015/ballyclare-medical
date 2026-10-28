require "rails_helper"
require "timeout"

RSpec.describe "Concurrent refund requests", :concurrency do
  self.use_transactional_tests = false

  it "prevents two concurrent refunds from exceeding the original payment" do
    payment = create(:payment, status: "succeeded", amount_cents: 5000,
      currency: "GBP", paid_at: Time.current)

    first_locked = Queue.new
    release_first = Queue.new
    second_pid = Queue.new
    first = nil
    second = nil

    begin
      first = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Payment.transaction do
            Payment.lock.find(payment.id)
            first_locked << true
            release_first.pop
            Payments::CreateRefund.new(
              payment: Payment.find(payment.id), amount_cents: 4000
            ).call
          end
        end
      end
      Timeout.timeout(10) { first_locked.pop }

      second = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          second_pid << connection.select_value("SELECT pg_backend_pid()")
          begin
            Payments::CreateRefund.new(
              payment: Payment.find(payment.id), amount_cents: 4000
            ).call
            :accepted
          rescue Payments::CreateRefund::AmountExceedsRefundable
            :rejected
          end
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
      expect(Timeout.timeout(10) { second.value }).to eq(:rejected)

      refunds = Refund.where(payment_id: payment.id)
      expect(refunds.count).to eq(1)
      expect(refunds.sum(:amount_cents)).to eq(4000)
      expect(refunds.first.status).to eq("pending")
    ensure
      release_first << true
      [first, second].compact.each { |thread| thread.join(10) }
    end
  end
end
