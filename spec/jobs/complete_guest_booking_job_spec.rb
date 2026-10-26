require "rails_helper"

RSpec.describe CompleteGuestBookingJob, type: :job do
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
      consultation_reason: "One-off consultation",
      status: "payment_pending", expires_at: 10.minutes.from_now
    )
  end
  let(:hold) do
    AppointmentHold.create!(appointment_slot: slot, guest_booking: guest,
      expires_at: 10.minutes.from_now)
  end
  let(:payment) do
    Payment.create!(appointment_hold: hold, guest_booking: guest,
      provider: "stripe", amount_cents: 5000, currency: practice.currency,
      status: "succeeded", idempotency_key: SecureRandom.uuid)
  end

  it "creates one external patient and one appointment after payment, even on retry" do
    payment
    expect {
      2.times { described_class.perform_now(payment.id) }
    }.to change(Patient, :count).by(1)
      .and change(Appointment, :count).by(1)

    expect(guest.reload.patient.patient_type).to eq("external")
    expect(payment.reload.appointment.patient).to eq(guest.patient)
    expect(payment.appointment.reason).to eq("One-off consultation")
  end

  it "does not create a patient before payment succeeds" do
    payment.update!(status: "processing")

    expect {
      described_class.perform_now(payment.id)
    }.to change(Patient, :count).by(0)
  end
end
