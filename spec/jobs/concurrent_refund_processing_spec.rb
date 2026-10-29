require "rails_helper"
require "timeout"

RSpec.describe "Concurrent Stripe refund processing", :concurrency do
  self.use_transactional_tests = false

  it "submits one Stripe refund while two workers compete for the same pending refund" do
    payment = create(:payment, status: "succeeded",
      provider_payment_id: "pi_concurrent_refund", paid_at: Time.current)
    refund = create(:refund, payment: payment, status: "pending",
      provider_refund_id: nil)
    original_key = refund.idempotency_key

    stripe_started = Queue.new
    release_stripe = Queue.new
    stripe_calls = Queue.new
    first = nil
    second = nil

    allow(Stripe::Refund).to receive(:create) do |params, options|
      stripe_calls << [ params, options ]
      stripe_started << true
      release_stripe.pop
      double(id: "re_concurrent_refund", status: "pending")
    end

    begin
      first = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ProcessRefundJob.new.perform(refund.id)
        end
      end
      Timeout.timeout(10) { stripe_started.pop }

      second = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ProcessRefundJob.new.perform(refund.id)
        end
      end
      Timeout.timeout(10) { second.value }
      expect(stripe_calls.size).to eq(1)

      release_stripe << true
      Timeout.timeout(10) { first.value }

      expect(stripe_calls.size).to eq(1)
      submitted_params, submitted_options = stripe_calls.pop
      expect(submitted_params[:payment_intent]).to eq(payment.provider_payment_id)
      expect(submitted_options[:idempotency_key]).to eq(original_key)
      expect(refund.reload.status).to eq("processing")
      expect(refund.provider_refund_id).to eq("re_concurrent_refund")
      expect(refund.idempotency_key).to eq(original_key)
    ensure
      release_stripe << true
      [ first, second ].compact.each { |thread| thread.join(10) }
    end
  end
end
