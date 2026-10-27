require "rails_helper"

RSpec.describe GuestBooking, type: :model do
  it "strips surrounding whitespace from guest names before saving" do
    practice = create(:practice)
    clinician = create(:staff_member, practice: practice, staff_type: "doctor")
    starts_at = 3.days.from_now.change(hour: 10, min: 0)
    availability_block = create(:availability_block, practice: practice,
      clinician: clinician, starts_at: starts_at - 1.hour,
      ends_at: starts_at + 1.hour, bookable_online: true)
    slot = create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: availability_block, starts_at: starts_at,
      ends_at: starts_at + 20.minutes)

    guest = described_class.create!(
      practice: practice, appointment_slot: slot,
      first_name: "  Mark  ", last_name: "  Visitor ",
      date_of_birth: Date.new(1990, 1, 1),
      email: "guest@example.com", phone: "07700900123",
      consultation_reason: "Consultation",
      status: "draft", expires_at: 30.minutes.from_now
    )

    expect(guest.reload.first_name).to eq("Mark")
    expect(guest.last_name).to eq("Visitor")
  end
end
