require "rails_helper"

RSpec.describe "Staff appointment medical group isolation", type: :request do
  let(:practice_a) { create(:practice) }
  let(:practice_b) { create(:practice) }
  let(:user) { create(:user) }

  before do
    create(:staff_member, user: user, practice: practice_a, access_level: "staff_admin")
    sign_in user
  end

  let!(:own_appointment) { create(:appointment, practice: practice_a) }
  let!(:other_appointment) { create(:appointment, practice: practice_b) }

  it "starts with distinct medical group ownership" do
    expect(practice_a.medical_group_id).not_to eq(practice_b.medical_group_id)
    expect(own_appointment.practice.medical_group_id).to eq(practice_a.medical_group_id)
    expect(other_appointment.practice.medical_group_id).to eq(practice_b.medical_group_id)
  end

  it "does not expose another group's appointment details" do
    get practice_appointment_path(other_appointment)

    expect(response).to have_http_status(:not_found)
  end

  it "does not permit changing another group's appointment status" do
    patch status_practice_appointment_path(other_appointment), params: { status: "confirmed" }

    expect(response).to have_http_status(:not_found)
    expect(other_appointment.reload.status).to eq("booked")
  end

  it "does not expose another group's appointment through the staff diary" do
    get practice_appointments_path, params: { date: other_appointment.appointment_slot.starts_at.to_date.iso8601 }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(other_appointment.id)
  end
end
