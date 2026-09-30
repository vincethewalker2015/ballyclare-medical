require "rails_helper"

RSpec.describe Payments::HandleRefundSucceeded do
  let(:payment) do
    create(
      :payment,
      status: "succeeded",
      amount_cents: 5000,
      currency: "GBP",
      paid_at: Time.current
    )
  end

  let!(:refund) do
    create(
      :refund,
      payment: payment,
      amount_cents: 2000,
      currency: "GBP",
      status: "processing",
      provider_refund_id: "re_test_123"
    )
  end

  let(:stripe_refund) do
    Stripe::Refund.construct_from(
      id: "re_test_123",
      object: "refund",
      amount: 2000,
      currency: "gbp",
      status: "succeeded"
    )
  end

  it "marks the refund as succeeded" do
    result = described_class.new(
      stripe_refund: stripe_refund
    ).call

    expect(result.reload.status).to eq("succeeded")
    expect(result.refunded_at).to be_present
  end

  it "is idempotent when the refund is already succeeded" do
    refund.update!(
      status: "succeeded",
      refunded_at: Time.current
    )

    original_time = refund.reload.refunded_at

    described_class.new(
      stripe_refund: stripe_refund
    ).call

    expect(refund.reload.refunded_at).to eq(original_time)
  end

  it "rejects an amount mismatch" do
    stripe_refund.amount = 1999

    expect {
      described_class.new(
        stripe_refund: stripe_refund
      ).call
    }.to raise_error(
      Payments::HandleRefundSucceeded::AmountMismatch
    )

    expect(refund.reload.status).to eq("processing")
  end

  it "rejects a currency mismatch" do
    stripe_refund.currency = "usd"

    expect {
      described_class.new(
        stripe_refund: stripe_refund
      ).call
    }.to raise_error(
      Payments::HandleRefundSucceeded::CurrencyMismatch
    )

    expect(refund.reload.status).to eq("processing")
  end

  it "raises when the refund cannot be found" do
    unknown_stripe_refund = Stripe::Refund.construct_from(
      id: "re_unknown",
      object: "refund",
      amount: 2000,
      currency: "gbp",
      status: "succeeded"
    )

    expect {
      described_class.new(
        stripe_refund: unknown_stripe_refund
      ).call
    }.to raise_error(
      Payments::HandleRefundSucceeded::RefundNotFound
    )
  end
end
