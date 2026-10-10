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
      id: "pi_failed_123",
      status: "canceled",
      amount: 5000,
      currency: appointment.practice.currency.downcase
    )
  end

  describe "#call" do
    it "marks the payment as failed" do
      described_class.new(
        payment_intent: payment_intent
      ).call

      expect(payment.reload.status).to eq("failed")
    end

    it "recovers a pending appointment payment using Stripe metadata" do
      payment.update!(
        provider_payment_id: nil,
        status: "pending"
      )

      allow(payment_intent)
        .to receive(:metadata)
        .and_return(
          { "payment_id" => payment.id }
        )

      described_class.new(
        payment_intent: payment_intent
      ).call

      payment.reload

      expect(payment).to have_attributes(
        provider_payment_id: "pi_failed_123",
        status: "failed"
      )

      expect(payment.appointment).to eq(appointment)
    end

    it "keeps an appointment payment in progress when Stripe requires confirmation" do
      allow(payment_intent)
        .to receive(:status)
        .and_return("requires_confirmation")

      described_class.new(
        payment_intent: payment_intent
      ).call

      expect(payment.reload.status).to eq("processing")
    end

    it "does not reopen an already failed payment" do
      payment.update!(status: "failed")

      allow(payment_intent)
        .to receive(:status)
        .and_return("requires_payment_method")

      result = described_class.new(
        payment_intent: payment_intent
      ).call

      expect(result.status).to eq("failed")
      expect(payment.reload.status).to eq("failed")
    end

    it "rejects a metadata-recovered payment with a mismatched amount" do
      payment.update!(
        provider_payment_id: nil,
        status: "pending"
      )

      allow(payment_intent)
        .to receive(:metadata)
        .and_return({ "payment_id" => payment.id })

      allow(payment_intent)
        .to receive(:amount)
        .and_return(6000)

      expect {
        described_class.new(payment_intent: payment_intent).call
      }.to raise_error(Payments::HandleFailed::AmountMismatch)

      expect(payment.reload).to have_attributes(
        provider_payment_id: nil,
        status: "pending"
      )
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

      allow(payment_intent)
        .to receive(:metadata)
        .and_return({})

      expect {
        described_class.new(
          payment_intent: payment_intent
        ).call
      }.to raise_error(
        Payments::HandleFailed::PaymentNotFound
      )
    end

    it "keeps an appointment payment in progress after a failed confirmation attempt" do
      allow(payment_intent)
        .to receive(:status)
        .and_return("requires_payment_method")

      described_class.new(
        payment_intent: payment_intent
      ).call

      expect(payment.reload.status).to eq("processing")
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

    it "locks the appointment before updating the payment" do
      expect(appointment)
        .to receive(:with_lock)
        .ordered
        .and_call_original

      expect(payment)
        .to receive(:with_lock)
        .ordered
        .and_call_original

      allow(Payment)
        .to receive(:find_by)
        .and_call_original

      allow(Payment)
        .to receive(:find_by)
        .with(
          provider: "stripe",
          provider_payment_id: "pi_failed_123"
        )
        .and_return(payment)

      allow(Appointment)
        .to receive(:find)
        .and_call_original

      allow(Appointment)
        .to receive(:find)
        .with(appointment.id)
        .and_return(appointment)

      described_class.new(
        payment_intent: payment_intent
      ).call

      expect(payment.reload.status).to eq("failed")
    end

    it "rejects a metadata-recovered payment with a mismatched currency" do
      payment.update!(
        provider_payment_id: nil,
        status: "pending"
      )

      allow(payment_intent)
        .to receive(:metadata)
        .and_return({ "payment_id" => payment.id })

      allow(payment_intent)
        .to receive(:currency)
        .and_return("usd")

      expect {
        described_class.new(payment_intent: payment_intent).call
      }.to raise_error(Payments::HandleFailed::CurrencyMismatch)

      expect(payment.reload).to have_attributes(
        provider_payment_id: nil,
        status: "pending"
      )
    end
  end
end
