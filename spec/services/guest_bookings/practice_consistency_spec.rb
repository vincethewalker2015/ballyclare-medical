require "rails_helper"

RSpec.describe GuestBookings::PracticeConsistency do
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
      first_name: "Guest", last_name: "Visitor", date_of_birth: Date.new(1990, 1, 1),
      email: "guest@example.com", phone: "07700900123",
      consultation_reason: "Consultation", status: "draft",
      expires_at: 30.minutes.from_now)
  end

  it "accepts consistent practice, clinician and slot relationships" do
    expect(described_class.valid?(guest: guest, slot: slot)).to be(true)
  end

  it "rejects a clinician belonging to another practice" do
    other_clinician = create(:staff_member, practice: create(:practice), staff_type: "doctor")
    slot.update_column(:clinician_id, other_clinician.id)

    expect(described_class.valid?(guest: guest, slot: slot.reload)).to be(false)
  end

  it "rejects an availability block belonging to another practice" do
    block.update_column(:practice_id, create(:practice).id)

    expect(described_class.valid?(guest: guest, slot: slot)).to be(false)
  end

  it "rejects a guest assigned to another practice" do
    guest.update_column(:practice_id, create(:practice).id)

    expect(described_class.valid?(guest: guest.reload, slot: slot)).to be(false)
  end
end
