require "rails_helper"

RSpec.describe PaymentProviders::StripeProvider::CreatePayment do
  let(:payment) do
    instance_double(
      Payment,
      id: "payment-123",
      amount_cents: 5000,
      currency: "GBP",
      idempotency_key: "idempotency-123",
      appointment_hold_id: "hold-123"
    )
  end

  let(:payment_intent) do
    instance_double(
      Stripe::PaymentIntent,
      id: "pi_test_123"
    )
  end

  describe "#call" do
    it "creates a Stripe PaymentIntent" do
      expect(Stripe::PaymentIntent)
        .to receive(:create)
        .with(
          {
            amount: 5000,
            currency: "gbp",
            metadata: {
              payment_id: "payment-123",
              appointment_hold_id: "hold-123"
            }
          },
          {
            idempotency_key: "idempotency-123"
          }
        )
        .and_return(payment_intent)

      allow(payment)
        .to receive(:update!)
        .with(
          provider_payment_id: "pi_test_123",
          status: "processing"
        )

      described_class.new(payment: payment).call
    end
    it "stores the Stripe PaymentIntent ID and marks the payment as processing" do
      allow(Stripe::PaymentIntent)
        .to receive(:create)
        .and_return(payment_intent)

      expect(payment)
        .to receive(:update!)
        .with(
          provider_payment_id: "pi_test_123",
          status: "processing"
        )

      described_class.new(payment: payment).call
    end
    it "does not update the payment when Stripe fails" do
      allow(Stripe::PaymentIntent)
        .to receive(:create)
        .and_raise(
          Stripe::APIConnectionError.new("Stripe is unavailable")
        )

      expect(payment).not_to receive(:update!)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(Stripe::APIConnectionError)
    end
  end
end
