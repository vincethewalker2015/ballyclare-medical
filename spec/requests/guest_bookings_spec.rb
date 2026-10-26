require "rails_helper"

RSpec.describe "Guest booking entry", type: :request do
  it "allows visitors to open the guest booking page without signing in" do
    get guest_booking_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Book as a guest")
    expect(response.body).to include("account or password")
    expect(response.body).to include("guest checkout")
  end

  it "shows online clinician slots without requiring a patient account" do
    practice = create(:practice)
    clinician = create(:staff_member, practice: practice, staff_type: "doctor")
    starts_at = 3.days.from_now.change(hour: 10, min: 0)
    block = create(:availability_block, practice: practice, clinician: clinician,
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)
    create(:appointment_slot, practice: practice, clinician: clinician,
      availability_block: block, starts_at: starts_at, ends_at: starts_at + 20.minutes)

    get guest_booking_path, params: { practice_id: practice.id, clinician_id: clinician.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(clinician.full_name)
    expect(response.body).to include(starts_at.in_time_zone(practice.timezone).strftime("%A, %d %B"))
    expect(AppointmentHold.count).to eq(0)
  end

  it "does not expose clinicians from another practice" do
    practice = create(:practice)
    other_practice = create(:practice)
    clinician = create(:staff_member, practice: other_practice, staff_type: "doctor")
    starts_at = 3.days.from_now.change(hour: 10, min: 0)
    create(:availability_block, practice: practice,
      clinician: create(:staff_member, practice: practice, staff_type: "doctor"),
      starts_at: starts_at - 1.hour, ends_at: starts_at + 1.hour, bookable_online: true)

    get guest_booking_path, params: { practice_id: practice.id, clinician_id: clinician.id }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.css("select[name=clinician_id] option").map { |option| option["value"] }).not_to include(clinician.id.to_s)
    expect(response.parsed_body.css("h3").map { |heading| heading.text.squish }).not_to include("Available appointments")
  end

  it "does not list practices without online availability" do
    practice = create(:practice, name: "No online appointments")
    create(:staff_member, practice: practice)

    get guest_booking_path

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.css("ul li").map { |item| item.text.squish }).not_to include(practice.name)
  end
end
