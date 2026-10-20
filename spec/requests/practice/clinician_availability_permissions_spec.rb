require "rails_helper"

RSpec.describe "Clinician availability permissions", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }
  let!(:clinician) do
    create(:staff_member, practice: practice, user: user,
      staff_type: "doctor", access_level: "staff_clinician")
  end
  let!(:colleague) { create(:staff_member, practice: practice, staff_type: "doctor") }
  let!(:colleague_block) do
    create(:availability_block, practice: practice, clinician: colleague)
  end

  before { sign_in user }

  it "only offers the signed-in clinician in the new availability form" do
    get new_practice_availability_block_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(clinician.full_name)
    expect(response.body).not_to include(colleague.full_name)
  end

  it "forbids editing a colleague's availability" do
    get edit_practice_availability_block_path(colleague_block)
    expect(response).to have_http_status(:forbidden)
  end

  it "forbids cancelling a colleague's availability" do
    patch cancel_practice_availability_block_path(colleague_block)
    expect(response).to have_http_status(:forbidden)
    expect(colleague_block.reload).to be_persisted
  end

  it "forbids reassigning their own availability to another clinician" do
    own_block = create(:availability_block, practice: practice, clinician: clinician)
    patch practice_availability_block_path(own_block), params: {
      availability_block: {
        clinician_id: colleague.id,
        date: Date.tomorrow.iso8601,
        starts_at: "09:00",
        ends_at: "12:00",
        slot_duration_minutes: 30,
        bookable_online: "1"
      }
    }

    expect(response).to have_http_status(:not_found)
    expect(own_block.reload.clinician_id).to eq(clinician.id)
  end
end
