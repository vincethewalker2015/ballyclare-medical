require "rails_helper"

RSpec.describe CleanupExpiredGuestBookingsJob, type: :job do
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

  def build_booking(status:, expires_at:)
    GuestBooking.create!(
      practice: practice, appointment_slot: slot,
      first_name: "Guest", last_name: "Visitor",
      date_of_birth: Date.new(1990, 1, 1),
      email: "visitor@example.com", phone: "07700900123",
      consultation_reason: "One-off consultation",
      status: status, expires_at: expires_at
    )
  end

  it "deletes expired draft records" do
    expired = build_booking(status: "draft", expires_at: 1.minute.ago)
    current = build_booking(status: "draft", expires_at: 10.minutes.from_now)

    described_class.perform_now

    expect(GuestBooking.exists?(expired.id)).to be(false)
    expect(GuestBooking.exists?(current.id)).to be(true)
  end

  it "preserves records awaiting payment or already completed" do
    pending = build_booking(status: "payment_pending", expires_at: 1.hour.ago)
    completed = build_booking(status: "completed", expires_at: 1.hour.ago)

    described_class.perform_now

    expect(GuestBooking.exists?(pending.id)).to be(true)
    expect(GuestBooking.exists?(completed.id)).to be(true)
  end

  it "preserves an expired draft that still owns a hold" do
    draft = build_booking(status: "draft", expires_at: 1.hour.ago)
    hold = AppointmentHold.create!(
      appointment_slot: slot, guest_booking: draft, expires_at: 1.minute.ago
    )

    described_class.perform_now

    expect(GuestBooking.exists?(draft.id)).to be(true)
    expect(AppointmentHold.exists?(hold.id)).to be(true)
  end

  it "preserves an expired draft linked to a payment" do
    draft = build_booking(status: "draft", expires_at: 1.hour.ago)
    payment = Payment.create!(
      guest_booking: draft, provider: "stripe", status: "processing",
      amount_cents: 5000, currency: practice.currency,
      idempotency_key: SecureRandom.uuid
    )

    described_class.perform_now

    expect(GuestBooking.exists?(draft.id)).to be(true)
    expect(Payment.exists?(payment.id)).to be(true)
  end

  it "is safe to run twice" do
    build_booking(status: "draft", expires_at: 1.minute.ago)

    expect { 2.times { described_class.perform_now } }.to change(GuestBooking, :count).by(-1)
  end
end
