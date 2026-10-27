require "rails_helper"

RSpec.describe ReconcileProcessingGuestPaymentsJob, type: :job do
  let(:practice) { create(:practice) }
  let(:clinician) { create(:staff_member, practice: practice, staff_type: "doctor") }
  let(:starts_at) { 3.days.from_now.change(hour: 10, min: 0) }
  let(:availability_block) do
    create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour)
  end
  let(:slot) do
    create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: availability_block, starts_at: starts_at,
      ends_at: starts_at + 20.minutes)
  end

  def guest_payment(status: "processing", intent_id: "pi_guest_declined")
    guest = GuestBooking.create!(
      practice: practice, appointment_slot: slot,
      first_name: "Guest", last_name: "Visitor",
      date_of_birth: Date.new(1990, 1, 1),
      email: "guest@example.com", phone: "07700900123",
      consultation_reason: "Consultation", status: "payment_pending",
      expires_at: 10.minutes.from_now
    )
    Payment.create!(
      guest_booking: guest, provider: "stripe", status: status,
      amount_cents: 6500, currency: practice.currency,
      provider_payment_id: intent_id, idempotency_key: SecureRandom.uuid
    )
  end

  it "reconciles a declined guest payment without creating a patient or appointment" do
    payment = guest_payment
    payment.update_columns(updated_at: 2.minutes.ago)
    intent = instance_double(Stripe::PaymentIntent,
      id: payment.provider_payment_id, status: "requires_payment_method",
      amount: 6500, currency: practice.currency.downcase)

    expect(Stripe::PaymentIntent).to receive(:retrieve)
      .with(payment.provider_payment_id).and_return(intent)

    expect { described_class.perform_now }.not_to change(Patient, :count)
    expect(payment.reload.status).to eq("failed")
    expect(payment.appointment_id).to be_nil
    expect(payment.guest_booking.patient_id).to be_nil
  end

  it "does not reconcile a recently processing guest payment" do
    payment = guest_payment
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)

    described_class.perform_now

    expect(payment.reload.status).to eq("processing")
  end

  it "does not reconcile a payment already marked failed" do
    payment = guest_payment(status: "failed")
    payment.update_columns(updated_at: 2.minutes.ago)
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)

    described_class.perform_now

    expect(payment.reload.status).to eq("failed")
  end
end
