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
    expect(guest.reload.attributes.slice("first_name", "last_name", "date_of_birth", "email", "phone", "consultation_reason").values).to all(be_nil)
    expect(payment.reload.guest_booking).to eq(guest)
    expect(payment.appointment.patient.email).to eq("visitor@example.com")
  end

  it "does not leave an external patient behind when a paid hold has expired" do
    payment
    hold.update!(expires_at: 1.minute.ago)

    expect {
      described_class.perform_now(payment.id)
    }.to change(Patient, :count).by(0)
      .and change(Appointment, :count).by(0)

    expect(payment.reload.status).to eq("requires_refund")
    expect(guest.reload.patient).to be_nil
  end

  it "does not create a patient when the paid slot is already booked" do
    payment
    other_patient = create(:patient, practice: practice)
    Appointment.create!(practice: practice, appointment_slot: slot,
      clinician: clinician, patient: other_patient, status: "booked", booked_at: Time.current)

    expect {
      described_class.perform_now(payment.id)
    }.to change(Patient, :count).by(0)

    expect(payment.reload.status).to eq("requires_refund")
    expect(guest.reload.patient).to be_nil
  end

  it "does not create a patient before payment succeeds" do
    payment.update!(status: "processing")

    expect {
      described_class.perform_now(payment.id)
    }.to change(Patient, :count).by(0)
  end

  it "marks a successful guest payment for refund when its hold is missing" do
    payment.update!(appointment_hold: nil)
    hold.destroy!

    expect {
      described_class.perform_now(payment.id)
    }.not_to change(Appointment, :count)

    expect(payment.reload.status).to eq("requires_refund")
    expect(payment.appointment).to be_nil
    expect(guest.reload.patient).to be_nil
  end

  it "marks a successful guest payment for refund when availability is withdrawn" do
    payment
    availability_block.update!(cancelled_at: Time.current)

    expect {
      described_class.perform_now(payment.id)
    }.not_to change(Appointment, :count)

    expect(payment.reload.status).to eq("requires_refund")
    expect(payment.appointment).to be_nil
    expect(guest.reload.patient).to be_nil
  end

  it "completes a delayed Stripe success once despite duplicate notifications and job retries" do
    payment.update!(status: "processing", provider_payment_id: "pi_delayed_guest_success")
    payment_intent = instance_double(
      Stripe::PaymentIntent,
      id: "pi_delayed_guest_success",
      amount_received: payment.amount_cents,
      currency: payment.currency.downcase
    )
    allow(CompleteGuestBookingJob).to receive(:perform_later)

    2.times { Payments::HandleSucceeded.new(payment_intent: payment_intent).call }

    expect(payment.reload.status).to eq("succeeded")
    expect(payment.appointment).to be_nil

    expect {
      2.times { described_class.perform_now(payment.id) }
    }.to change(Appointment, :count).by(1)
      .and change(Patient, :count).by(1)

    appointment = payment.reload.appointment
    expect(appointment).to be_present
    expect(appointment.appointment_charges.active.count).to eq(1)
    expect(appointment.appointment_charges.active.sole.amount_cents).to eq(payment.amount_cents)
    expect(payment.reload.status).to eq("succeeded")
    expect(payment.refunds.count).to eq(0)
  end

  it "keeps a late successful payment marked for refund after repeated Stripe notifications" do
    payment.update!(status: "processing", provider_payment_id: "pi_late_guest_success")
    hold.update!(expires_at: 1.minute.ago)
    payment_intent = instance_double(
      Stripe::PaymentIntent,
      id: "pi_late_guest_success",
      amount_received: payment.amount_cents,
      currency: payment.currency.downcase
    )
    allow(CompleteGuestBookingJob).to receive(:perform_later)

    2.times { Payments::HandleSucceeded.new(payment_intent: payment_intent).call }

    expect {
      2.times { described_class.perform_now(payment.id) }
    }.not_to change(Appointment, :count)

    expect(payment.reload.status).to eq("requires_refund")
    expect(payment.appointment).to be_nil
    expect(guest.reload.patient).to be_nil

    Payments::HandleSucceeded.new(payment_intent: payment_intent).call
    expect(payment.reload.status).to eq("requires_refund")
    expect(payment.appointment).to be_nil
  end
end
