require "rails_helper"

RSpec.describe Payments::TakeHoldPayment do
  let(:practice) { create(:practice) }
  let(:clinician) { create(:staff_member, practice: practice, staff_type: "doctor") }
  let(:starts_at) { 3.days.from_now.change(hour: 10, min: 0) }
  let(:availability_block) do
    create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)
  end
  let(:slot) do
    create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: availability_block, starts_at: starts_at,
      ends_at: starts_at + 20.minutes)
  end
  let(:guest) do
    GuestBooking.create!(
      practice: practice, appointment_slot: slot,
      first_name: "Guest", last_name: "Visitor",
      date_of_birth: Date.new(1990, 1, 1),
      email: "visitor@example.com", phone: "07700900123",
      consultation_reason: "Consultation",
      status: "payment_pending", expires_at: 10.minutes.from_now
    )
  end
  let(:hold) do
    AppointmentHold.create!(
      appointment_slot: slot, guest_booking: guest, expires_at: 10.minutes.from_now
    )
  end

  it "preserves one payment and its Stripe idempotency key after an ambiguous API timeout" do
    create(:consultation_fee, practice: practice, clinician_type: "doctor")
    seen_keys = []
    allow(Stripe::PaymentIntent).to receive(:create) do |_params, options|
      seen_keys << options.fetch(:idempotency_key)
      raise Stripe::APIConnectionError, "Stripe connection timed out"
    end

    2.times do
      expect {
        described_class.new(hold: hold).call
      }.to raise_error(Stripe::APIConnectionError)
    end

    expect(hold.payments.count).to eq(1)
    payment = hold.payments.sole
    expect(payment.status).to eq("pending")
    expect(payment.provider_payment_id).to be_nil
    expect(seen_keys).to eq([ payment.idempotency_key, payment.idempotency_key ])
    expect(Appointment.where(appointment_slot: slot)).to be_empty
  end
end
