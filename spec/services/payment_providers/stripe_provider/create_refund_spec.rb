require "rails_helper"

RSpec.describe PaymentProviders::StripeProvider::CreateRefund do
  let(:payment) do
    create(
      :payment,
      status: "succeeded",
      provider: "stripe",
      provider_payment_id: "pi_test_123",
      amount_cents: 5000,
      currency: "GBP",
      paid_at: Time.current
    )
  end

  let(:refund) do
    create(
      :refund,
      payment: payment,
      amount_cents: 2000,
      currency: "GBP",
      status: "pending"
    )
  end

  let(:stripe_refund) do
    Stripe::Refund.construct_from(
      id: "re_test_123",
      object: "refund",
      amount: 2000,
      currency: "gbp",
      status: "pending"
    )
  end

  it "creates a Stripe refund with the correct details" do
    expect(Stripe::Refund).to receive(:create).with(
      {
        payment_intent: "pi_test_123",
        amount: 2000,
        metadata: {
          refund_id: refund.id,
          payment_id: payment.id
        }
      },
      {
        idempotency_key: refund.idempotency_key
      }
    ).and_return(stripe_refund)

    described_class.new(refund: refund).call
  end

  it "stores the Stripe refund ID and marks the refund as processing" do
    allow(Stripe::Refund)
      .to receive(:create)
      .and_return(stripe_refund)

    described_class.new(refund: refund).call

    refund.reload

    expect(refund.provider_refund_id).to eq("re_test_123")
    expect(refund.status).to eq("processing")
  end

  it "does not update the local refund when Stripe fails" do
    allow(Stripe::Refund)
      .to receive(:create)
      .and_raise(
        Stripe::APIConnectionError.new(
          "Connection failed"
        )
      )

    expect {
      described_class.new(refund: refund).call
    }.to raise_error(Stripe::APIConnectionError)

    refund.reload

    expect(refund.status).to eq("pending")
    expect(refund.provider_refund_id).to be_nil
  end

  it "does not overwrite a refund already marked succeeded by a webhook" do
    allow(Stripe::Refund).to receive(:create) do
      # Simulate the webhook succeeding before the Stripe API returns.
      refund.update!(
        provider_refund_id: "re_test_123",
        status: "succeeded",
        refunded_at: Time.current
      )

      stripe_refund
    end

    described_class.new(refund: refund).call

    refund.reload

    expect(refund.provider_refund_id).to eq("re_test_123")
    expect(refund.status).to eq("succeeded")
    expect(refund.refunded_at).to be_present
  end

  it "rejects a conflicting Stripe refund ID without changing the refund" do
    refund.update!(
      provider_refund_id: "re_existing_456",
      status: "processing"
    )

    allow(Stripe::Refund)
      .to receive(:create)
      .and_return(stripe_refund)

    expect {
      described_class.new(refund: refund).call
    }.to raise_error(
      PaymentProviders::StripeProvider::CreateRefund::ProviderRefundMismatch
    )

    refund.reload

    expect(refund.provider_refund_id).to eq("re_existing_456")
    expect(refund.status).to eq("processing")
  end
end
