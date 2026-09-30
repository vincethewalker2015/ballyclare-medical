require "rails_helper"

RSpec.describe Payments::CreateRefund do
  let(:payment) do
    create(
      :payment,
      status: "succeeded",
      amount_cents: 5000,
      currency: "GBP",
      paid_at: Time.current
    )
  end

  it "creates a pending refund" do
    refund = described_class.new(
      payment: payment,
      amount_cents: 2000,
      reason: "Patient requested cancellation"
    ).call

    expect(refund).to be_persisted
    expect(refund.amount_cents).to eq(2000)
    expect(refund.currency).to eq("GBP")
    expect(refund.status).to eq("pending")
    expect(refund.requested_at).to be_present
    expect(refund.reason).to eq("Patient requested cancellation")
    expect(refund.idempotency_key).to be_present
  end

  it "allows a full refund" do
    refund = described_class.new(
      payment: payment,
      amount_cents: 5000
    ).call

    expect(refund.amount_cents).to eq(5000)
  end

  it "allows partial refunds up to the payment amount" do
    create(
      :refund,
      payment: payment,
      amount_cents: 2000,
      currency: "GBP",
      status: "succeeded"
    )

    refund = described_class.new(
      payment: payment,
      amount_cents: 3000
    ).call

    expect(refund.amount_cents).to eq(3000)
  end

  it "rejects refunds exceeding the remaining amount" do
    create(
      :refund,
      payment: payment,
      amount_cents: 2000,
      currency: "GBP",
      status: "succeeded"
    )

    expect {
      described_class.new(
        payment: payment,
        amount_cents: 3001
      ).call
    }.to raise_error(
      Payments::CreateRefund::AmountExceedsRefundable
    )
  end

  it "counts pending refunds against the refundable amount" do
    create(
      :refund,
      payment: payment,
      amount_cents: 4000,
      currency: "GBP",
      status: "pending"
    )

    expect {
      described_class.new(
        payment: payment,
        amount_cents: 2000
      ).call
    }.to raise_error(
      Payments::CreateRefund::AmountExceedsRefundable
    )
  end

  it "does not count failed refunds against the refundable amount" do
    create(
      :refund,
      payment: payment,
      amount_cents: 4000,
      currency: "GBP",
      status: "failed"
    )

    refund = described_class.new(
      payment: payment,
      amount_cents: 5000
    ).call

    expect(refund.amount_cents).to eq(5000)
  end

  it "allows a payment requiring refund to be refunded" do
    payment.update!(status: "requires_refund")

    refund = described_class.new(
      payment: payment,
      amount_cents: 5000
    ).call

    expect(refund).to be_persisted
  end

  it "rejects an unpaid payment" do
    payment.update!(
      status: "processing",
      paid_at: nil
    )

    expect {
      described_class.new(
        payment: payment,
        amount_cents: 5000
      ).call
    }.to raise_error(
      Payments::CreateRefund::PaymentNotRefundable
    )
  end
end
