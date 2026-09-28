require "rails_helper"

RSpec.describe Payments::HandleSucceeded do
  let(:appointment) { create(:appointment) }

  let!(:payment) do
    Payment.create!(
      appointment: appointment,
      patient: appointment.patient,
      provider: "stripe",
      provider_payment_id: "pi_test_123",
      amount_cents: 5000,
      currency: "GBP",
      status: "processing",
      idempotency_key: SecureRandom.uuid
    )
  end

  let(:payment_intent) do
    instance_double(
      Stripe::PaymentIntent,
      id: "pi_test_123",
      amount_received: 5000,
      currency: "gbp"
    )
  end

  describe "#call" do
    it "marks the payment as succeeded" do
      described_class.new(
        payment_intent: payment_intent
      ).call

      payment.reload

      expect(payment.status).to eq("succeeded")
      expect(payment.paid_at).to be_present
    end

    it "is idempotent when the payment is already succeeded" do
      payment.update!(
        status: "succeeded",
        paid_at: 5.minutes.ago
      )

      original_paid_at = payment.paid_at

      described_class.new(
        payment_intent: payment_intent
      ).call

      expect(payment.reload.paid_at).to eq(original_paid_at)
    end

    it "rejects an amount mismatch" do
      allow(payment_intent)
        .to receive(:amount_received)
        .and_return(4000)

      expect {
        described_class.new(
          payment_intent: payment_intent
        ).call
      }.to raise_error(
        Payments::HandleSucceeded::AmountMismatch
      )

      expect(payment.reload.status).to eq("processing")
    end

    it "rejects a currency mismatch" do
      allow(payment_intent)
        .to receive(:currency)
        .and_return("usd")

      expect {
        described_class.new(
          payment_intent: payment_intent
        ).call
      }.to raise_error(
        Payments::HandleSucceeded::CurrencyMismatch
      )

      expect(payment.reload.status).to eq("processing")
    end

    it "raises when the local payment cannot be found" do
      allow(payment_intent)
        .to receive(:id)
        .and_return("pi_unknown")

      expect {
        described_class.new(
          payment_intent: payment_intent
        ).call
      }.to raise_error(
        Payments::HandleSucceeded::PaymentNotFound
      )
    end
  end
end
