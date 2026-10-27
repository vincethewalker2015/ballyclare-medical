require "rails_helper"

RSpec.describe RecoverGuestRefundsJob, type: :job do
  let(:practice) { create(:practice) }
  let(:clinician) { create(:staff_member, practice: practice, staff_type: "doctor") }
  let(:starts_at) { 3.days.from_now.change(hour: 10, min: 0) }
  let(:block) do
    create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)
  end
  let(:slot) do
    create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: block, starts_at: starts_at, ends_at: starts_at + 20.minutes)
  end
  let(:guest) do
    GuestBooking.create!(practice: practice, appointment_slot: slot,
      first_name: "Guest", last_name: "Visitor",
      date_of_birth: Date.new(1990, 1, 1), email: "guest@example.com",
      phone: "07700900123", consultation_reason: "Consultation",
      status: "payment_pending", expires_at: 10.minutes.from_now)
  end
  let!(:payment) do
    Payment.create!(guest_booking: guest, provider: "stripe",
      provider_payment_id: "pi_refund_guest", amount_cents: 4000,
      currency: practice.currency, status: "requires_refund",
      idempotency_key: SecureRandom.uuid)
  end

  it "creates and queues a full refund once across repeated runs" do
    allow(ProcessRefundJob).to receive(:perform_later)

    expect {
      2.times { described_class.perform_now }
    }.to change(Refund, :count).by(1)

    refund = payment.refunds.sole
    expect(refund.status).to eq("pending")
    expect(refund.amount_cents).to eq(4000)
    expect(ProcessRefundJob).to have_received(:perform_later).with(refund.id).twice
    expect(payment.reload.appointment_id).to be_nil
    expect(guest.reload.patient_id).to be_nil
  end

  it "only refunds the unallocated balance" do
    create(:refund, payment: payment, amount_cents: 1000,
      currency: practice.currency, status: "succeeded")
    allow(ProcessRefundJob).to receive(:perform_later)

    described_class.perform_now

    expect(payment.refunds.where(status: "pending").sole.amount_cents).to eq(3000)
  end

  it "does not create another refund after a failed refund" do
    create(:refund, payment: payment, amount_cents: 4000,
      currency: practice.currency, status: "failed",
      provider_refund_id: "re_failed")
    expect(ProcessRefundJob).not_to receive(:perform_later)

    expect { described_class.perform_now }.not_to change(Refund, :count)
  end
end
