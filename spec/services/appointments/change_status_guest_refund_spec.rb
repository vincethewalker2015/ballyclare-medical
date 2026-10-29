require "rails_helper"

RSpec.describe Appointments::ChangeStatus, "paid guest appointment cancellation" do
  let(:practice) { create(:practice) }
  let(:staff_user) { create(:user) }
  let(:appointment) { create(:appointment, practice: practice, status: "booked") }
  let(:guest_booking) do
    GuestBooking.create!(
      practice: practice,
      appointment_slot: appointment.appointment_slot,
      patient: appointment.patient,
      first_name: "Guest",
      last_name: "Visitor",
      date_of_birth: Date.new(1990, 1, 1),
      email: "visitor@example.com",
      phone: "07700900123",
      consultation_reason: "Consultation",
      status: "completed",
      expires_at: 1.hour.from_now
    )
  end
  let!(:payment) do
    Payment.create!(
      guest_booking: guest_booking,
      patient: appointment.patient,
      appointment: appointment,
      provider: "stripe",
      provider_payment_id: "pi_guest_cancel_#{SecureRandom.hex(6)}",
      amount_cents: 4000,
      currency: practice.currency,
      status: "succeeded",
      paid_at: Time.current,
      idempotency_key: SecureRandom.uuid
    )
  end

  def cancel_appointment
    described_class.new(
      appointment: appointment,
      to_status: "cancelled",
      changed_by: staff_user
    ).call
  end

  it "records exactly one full refund for a successful guest payment and queues processing" do
    allow(ProcessRefundJob).to receive(:perform_later)

    expect { cancel_appointment }.to change(Refund, :count).by(1)

    refund = payment.refunds.sole
    expect(refund).to have_attributes(
      status: "pending",
      amount_cents: 4000,
      currency: practice.currency,
      requested_by: staff_user
    )
    expect(refund.idempotency_key).to be_present
    expect(refund.payment.guest_booking).to eq(guest_booking)
    expect(appointment.reload.status).to eq("cancelled")
    expect(ProcessRefundJob).to have_received(:perform_later).with(refund.id).once
  end

  it "only refunds the remaining balance of a partially refunded guest payment" do
    create(:refund, payment: payment, amount_cents: 1500,
      currency: practice.currency, status: "succeeded")
    allow(ProcessRefundJob).to receive(:perform_later)

    expect { cancel_appointment }.to change(Refund, :count).by(1)
    expect(payment.refunds.where(status: "pending").sole.amount_cents).to eq(2500)
  end

  it "does not issue another refund for an already fully refunded guest payment" do
    create(:refund, payment: payment, amount_cents: 4000,
      currency: practice.currency, status: "succeeded")
    expect(ProcessRefundJob).not_to receive(:perform_later)

    expect { cancel_appointment }.not_to change(Refund, :count)
    expect(appointment.reload.status).to eq("cancelled")
  end
end
