require "rails_helper"

RSpec.describe PaymentProviders::StripeProvider::CancelPayment do
  describe "#call" do
    it "cancels the known Stripe PaymentIntent" do
      payment = build_stubbed(
        :payment,
        provider: "stripe",
        provider_payment_id: "pi_123"
      )

      stripe_intent = double(
        "Stripe::PaymentIntent",
        id: "pi_123",
        status: "canceled"
      )

      expect(Stripe::PaymentIntent)
        .to receive(:cancel)
        .with("pi_123")
        .and_return(stripe_intent)

      result = described_class.new(payment: payment).call

      expect(result).to eq(stripe_intent)
    end

    it "rejects payments without a known Stripe PaymentIntent" do
      payment = build_stubbed(
        :payment,
        provider: "stripe",
        provider_payment_id: nil
      )

      expect(Stripe::PaymentIntent)
        .not_to receive(:cancel)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        ArgumentError,
        "Stripe PaymentIntent ID is missing"
      )
    end

    it "rejects a Stripe response that does not confirm cancellation" do
      payment = build_stubbed(
        :payment,
        provider: "stripe",
        provider_payment_id: "pi_123"
      )

      stripe_intent = double(
        "Stripe::PaymentIntent",
        id: "pi_123",
        status: "succeeded"
      )

      allow(Stripe::PaymentIntent)
        .to receive(:cancel)
        .with("pi_123")
        .and_return(stripe_intent)

      expect {
        described_class.new(payment: payment).call
      }.to raise_error(
        PaymentProviders::StripeProvider::CancelPayment::CancellationNotConfirmed
      )
    end

    it "uses an explicitly supplied PaymentIntent ID" do
      payment = build_stubbed(
        :payment,
        provider: "stripe",
        provider_payment_id: "pi_replacement"
      )

      stripe_intent = double(
        "Stripe::PaymentIntent",
        id: "pi_original",
        status: "canceled"
      )

      expect(Stripe::PaymentIntent)
        .to receive(:cancel)
        .with("pi_original")
        .and_return(stripe_intent)

      result = described_class.new(
        payment: payment,
        payment_intent_id: "pi_original"
      ).call

      expect(result).to eq(stripe_intent)
    end
  end
end
