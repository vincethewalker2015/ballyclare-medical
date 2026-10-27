require "rails_helper"

RSpec.describe Payments::HandleFailed, "guest payments" do
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
    GuestBooking.create!(practice: practice, appointment_slot: slot,
      first_name: "Guest", last_name: "Visitor", date_of_birth: Date.new(1990, 1, 1),
      email: "visitor@example.com", phone: "07700900123",
      consultation_reason: "One-off consultation", status: "payment_pending",
      expires_at: 10.minutes.from_now)
  end
  let(:hold) do
    AppointmentHold.create!(appointment_slot: slot, guest_booking: guest,
      expires_at: 10.minutes.from_now)
  end
  let!(:payment) do
    Payment.create!(appointment_hold: hold, guest_booking: guest,
      provider: "stripe", provider_payment_id: "pi_guest_failure",
      amount_cents: 5000, currency: practice.currency, status: "processing",
      idempotency_key: SecureRandom.uuid)
  end
  let(:intent) do
    instance_double(Stripe::PaymentIntent, id: "pi_guest_failure",
      amount: 5000, currency: practice.currency.downcase,
      status: "requires_payment_method")
  end

  def handle_failure
    described_class.new(payment_intent: intent).call
  end

  it "marks a failed guest attempt without creating a patient or appointment" do
    expect { handle_failure }.to change(Patient, :count).by(0)
      .and change(Appointment, :count).by(0)

    expect(payment.reload.status).to eq("failed")
    expect(guest.reload.patient).to be_nil
    expect(hold.reload).to be_present
  end

  it "does not create a patient or appointment for a cancelled Stripe intent" do
    allow(intent).to receive(:status).and_return("canceled")

    expect { handle_failure }.to change(Patient, :count).by(0)
      .and change(Appointment, :count).by(0)

    expect(payment.reload.status).to eq("failed")
    expect(guest.reload.patient).to be_nil
  end

  it "is idempotent when Stripe repeats a failed event" do
    2.times { handle_failure }

    expect(payment.reload.status).to eq("failed")
    expect(guest.reload.patient).to be_nil
    expect(payment.appointment).to be_nil
  end

  it "does not overwrite an already succeeded guest payment" do
    payment.update!(status: "succeeded", paid_at: Time.current)

    handle_failure

    expect(payment.reload.status).to eq("succeeded")
    expect(guest.reload.patient).to be_nil
  end

  it "stops blocking the slot when its hold expires" do
    handle_failure
    hold.update!(expires_at: 1.minute.ago)

    expect(slot.appointment_holds.active).to be_empty
    expect(guest.reload.patient).to be_nil
    expect(payment.reload.appointment).to be_nil
  end
end
