require "rails_helper"

RSpec.describe Payments::HandleSucceeded do
  let(:appointment_slot) { create(:appointment_slot) }

  let(:patient) do
    create(
      :patient,
      practice: appointment_slot.practice
    )
  end

  let(:appointment_hold) do
    appointment_slot.hold_for!(
      patient: patient
    )
  end

  let!(:payment) do
    Payment.create!(
      appointment_hold: appointment_hold,
      patient: patient,
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
    it "marks the payment as succeeded and completes the booking" do
      described_class.new(
        payment_intent: payment_intent
      ).call

      payment.reload

      expect(payment.status).to eq("succeeded")
      expect(payment.paid_at).to be_present

      expect(payment.appointment).to be_present
      expect(payment.appointment_hold).to be_nil

      expect(payment.appointment.patient).to eq(patient)
      expect(payment.appointment.appointment_slot).to eq(appointment_slot)

      expect {
        appointment_hold.reload
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

   it "completes the booking when the payment is already succeeded" do
      payment.update!(
        status: "succeeded",
        paid_at: 5.minutes.ago
      )

      original_paid_at = payment.paid_at

      booking_service = instance_double(Payments::CompleteBooking)

      expect(Payments::CompleteBooking)
        .to receive(:new)
        .with(payment: payment)
        .and_return(booking_service)

      expect(booking_service)
        .to receive(:call)

      described_class.new(
        payment_intent: payment_intent
      ).call

      payment.reload

      expect(payment.status).to eq("succeeded")
      expect(payment.paid_at).to eq(original_paid_at)
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
    it "completes the booking after marking the payment as succeeded" do
      booking_service = instance_double(Payments::CompleteBooking)

      expect(Payments::CompleteBooking)
        .to receive(:new)
        .with(payment: payment)
        .and_return(booking_service)

      expect(booking_service)
        .to receive(:call)

      described_class.new(
        payment_intent: payment_intent
      ).call

      expect(payment.reload.status).to eq("succeeded")
      expect(payment.paid_at).to be_present
    end

    it "marks the payment as requiring a refund when the slot is unavailable" do
  booking_service = instance_double(Payments::CompleteBooking)

  allow(Payments::CompleteBooking)
    .to receive(:new)
    .with(payment: payment)
    .and_return(booking_service)

  allow(booking_service)
    .to receive(:call)
    .and_raise(
      Payments::CompleteBooking::SlotUnavailable,
      "Appointment slot has already been booked"
    )

  described_class.new(
    payment_intent: payment_intent
  ).call

  payment.reload

  expect(payment.status).to eq("requires_refund")
  expect(payment.paid_at).to be_present
end

    it "marks the payment as requiring a refund when the hold has expired" do
      booking_service = instance_double(Payments::CompleteBooking)

      allow(Payments::CompleteBooking)
        .to receive(:new)
        .with(payment: payment)
        .and_return(booking_service)

      allow(booking_service)
        .to receive(:call)
        .and_raise(
          Payments::CompleteBooking::HoldExpired,
          "Appointment hold has expired"
        )

      described_class.new(
        payment_intent: payment_intent
      ).call

      payment.reload

      expect(payment.status).to eq("requires_refund")
      expect(payment.paid_at).to be_present
    end
  end
end
