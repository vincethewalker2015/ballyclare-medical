require "rails_helper"

RSpec.describe Payments::ReconcileStripeStatus do
  let(:payment) { create(:payment, status: "processing", provider_payment_id: "pi_status_test", updated_at: 10.seconds.ago) }

  it "uses the existing success handler for successful Stripe payments" do
    intent = instance_double(Stripe::PaymentIntent, status: "succeeded")
    allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_status_test").and_return(intent)
    expect(Payments::HandleSucceeded).to receive(:new).with(payment_intent: intent).and_return(double(call: nil))
    described_class.new(payment: payment).call
  end

  it "uses staff cancellation reconciliation for appointment payments" do
    intent = instance_double(Stripe::PaymentIntent, status: "canceled")
    allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent)
    expect(Payments::ReconcileAppointmentPayment).to receive(:new).with(payment: payment).and_return(double(call: nil))
    described_class.new(payment: payment).call
  end

  it "recovers a succeeded hold payment that has not completed its appointment" do
    slot = create(:appointment_slot)
    patient = create(:patient, practice: slot.practice)
    hold = slot.hold_for!(patient: patient)
    pending_booking_payment = Payment.create!(
      appointment_hold: hold,
      patient: patient,
      provider: "stripe",
      provider_payment_id: "pi_unfinished_booking",
      amount_cents: 5000,
      currency: slot.practice.currency,
      status: "succeeded",
      paid_at: 1.minute.ago,
      idempotency_key: SecureRandom.uuid
    )
    pending_booking_payment.update_columns(updated_at: 10.seconds.ago)
    intent = instance_double(
      Stripe::PaymentIntent,
      id: "pi_unfinished_booking",
      status: "succeeded",
      amount_received: 5000,
      currency: slot.practice.currency.downcase
    )
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_unfinished_booking").and_return(intent)

    expect {
      described_class.new(payment: pending_booking_payment).call
    }.to change(Appointment, :count).by(1)

    expect(pending_booking_payment.reload.appointment).to be_present
    expect(pending_booking_payment.appointment.appointment_charges.active.count).to eq(1)
  end

  it "does not contact Stripe for payments that are not processing" do
    payment.update!(status: "succeeded")
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)
    described_class.new(payment: payment).call
  end

  it "does not reconcile recently updated payments" do
    payment.update!(updated_at: Time.current)
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)
    described_class.new(payment: payment).call
  end
end
