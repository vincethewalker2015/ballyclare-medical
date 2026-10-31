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

  it "handles a successful webhook before the Stripe refund ID is saved" do
    refund.update!(
      status: "pending",
      provider_refund_id: nil
    )

    stripe_refund.metadata = Stripe::StripeObject.construct_from(
      refund_id: refund.id,
      payment_id: payment.id
    )

    result = described_class.new(
      stripe_refund: stripe_refund
    ).call

    expect(result.id).to eq(refund.id)

    expect(refund.reload).to have_attributes(
      provider_refund_id: "re_test_123",
      status: "succeeded"
    )

    expect(refund.refunded_at).to be_present
  end

  it "accepts Stripe string metadata IDs for a matching refund and payment" do
    refund.update!(status: "pending", provider_refund_id: nil)

    stripe_refund.metadata = Stripe::StripeObject.construct_from(
      refund_id: refund.id.to_s,
      payment_id: payment.id.to_s
    )

    result = described_class.new(stripe_refund: stripe_refund).call

    expect(result.id).to eq(refund.id)
    expect(refund.reload).to have_attributes(
      provider_refund_id: "re_test_123",
      status: "succeeded"
    )
    expect(refund.refunded_at).to be_present
  end

  it "rejects a conflicting Stripe refund ID supplied through metadata" do
    refund.update!(
      provider_refund_id: "re_existing_456",
      status: "processing"
    )

    stripe_refund.metadata = Stripe::StripeObject.construct_from(
      refund_id: refund.id,
      payment_id: payment.id
    )

    expect {
      described_class.new(
        stripe_refund: stripe_refund
      ).call
    }.to raise_error(
      Payments::HandleRefundSucceeded::ProviderRefundMismatch
    )

    refund.reload

    expect(refund.provider_refund_id).to eq("re_existing_456")
    expect(refund.status).to eq("processing")
    expect(refund.refunded_at).to be_nil
  end

  it "rejects mismatched payment metadata without updating the refund" do
    refund.update!(
      status: "pending",
      provider_refund_id: nil
    )

    another_payment = create(
      :payment,
      status: "succeeded",
      amount_cents: 5000,
      currency: "GBP",
      paid_at: Time.current
    )

    stripe_refund.metadata = Stripe::StripeObject.construct_from(
      refund_id: refund.id,
      payment_id: another_payment.id
    )

    expect {
      described_class.new(
        stripe_refund: stripe_refund
      ).call
    }.to raise_error(
      Payments::HandleRefundSucceeded::PaymentMismatch
    )

    refund.reload

    expect(refund.status).to eq("pending")
    expect(refund.provider_refund_id).to be_nil
    expect(refund.refunded_at).to be_nil
  end

  it "rejects a mismatched Stripe PaymentIntent" do
    stripe_refund.payment_intent = "pi_wrong_payment_456"

    expect {
      described_class.new(
        stripe_refund: stripe_refund
      ).call
    }.to raise_error(
      Payments::HandleRefundSucceeded::PaymentMismatch
    )

    refund.reload

    expect(refund.status).to eq("processing")
    expect(refund.provider_refund_id).to eq("re_test_123")
    expect(refund.refunded_at).to be_nil
  end
end
