require "rails_helper"

RSpec.describe Payments::HandleFailed do
  let(:appointment) { create(:appointment) }

  let!(:payment) do
    create(
      :payment,
      appointment: appointment,
      appointment_hold: nil,
      patient: appointment.patient,
      provider: "stripe",
      provider_payment_id: "pi_failed_123",
      amount_cents: 5000,
      currency: appointment.practice.currency,
      status: "processing"
    )
  end

  let(:payment_intent) do
    instance_double(
      Stripe::PaymentIntent,
      id: "pi_failed_123"
    )
  end

  describe "#call" do
    it "marks the payment as failed" do
      described_class.new(
        payment_intent: payment_intent
      ).call

      expect(payment.reload.status).to eq("failed")
    end

    it "does not alter the appointment" do
      expect {
        described_class.new(
          payment_intent: payment_intent
        ).call
      }.not_to change(Appointment, :count)

      expect(payment.reload.appointment).to eq(appointment)
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
        Payments::HandleFailed::PaymentNotFound
      )
    end
    it "is idempotent when the payment is already failed" do
      payment.update!(status: "failed")

      result = described_class.new(
        payment_intent: payment_intent
      ).call

      expect(result.status).to eq("failed")
      expect(payment.reload.status).to eq("failed")
    end

    it "does not overwrite a succeeded payment" do
      paid_at = 5.minutes.ago

      payment.update!(
        status: "succeeded",
        paid_at: paid_at
      )

      result = described_class.new(
        payment_intent: payment_intent
      ).call

      expect(result.status).to eq("succeeded")

      payment.reload

      expect(payment.status).to eq("succeeded")
      expect(payment.paid_at).to be_within(1.second).of(paid_at)
    end
  end
end
