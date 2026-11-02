require "rails_helper"

RSpec.describe "Staff practice selection", type: :request do
  let(:group) { create(:medical_group) }
  let(:home) { create(:practice, medical_group: group) }
  let(:sibling) { create(:practice, medical_group: group) }
  let(:outside) { create(:practice) }
  let(:user) { create(:user) }
  let!(:membership) { create(:staff_member, user: user, practice: home, access_level: "staff_admin") }
  let!(:home_patient) { create(:patient, practice: home, first_name: "HomePatient") }
  let!(:sibling_patient) { create(:patient, practice: sibling, first_name: "SiblingPatient") }
  let!(:outside_patient) { create(:patient, practice: outside, first_name: "OutsidePatient") }

  before { sign_in user }

  it "defaults to the staff member's home practice" do
    get practice_patients_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("HomePatient")
    expect(response.body).not_to include("SiblingPatient")
  end

  it "switches to a sibling practice and scopes subsequent patient requests" do
    patch practice_selection_path, params: { practice_id: sibling.id }

    expect(response).to redirect_to(practice_appointments_path)

    get practice_patients_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("SiblingPatient")
    expect(response.body).not_to include("HomePatient")
    expect(response.body).not_to include("OutsidePatient")
  end

  it "rejects switching to an unrelated group and preserves home scope" do
    patch practice_selection_path, params: { practice_id: outside.id }

    expect(response).to have_http_status(:forbidden)

    get practice_patients_path

    expect(response.body).to include("HomePatient")
    expect(response.body).not_to include("OutsidePatient")
  end

  it "rejects an unknown practice" do
    patch practice_selection_path, params: { practice_id: SecureRandom.uuid }

    expect(response).to have_http_status(:forbidden)
  end

  it "rejects switching after membership is deactivated" do
    membership.update!(active: false)

    patch practice_selection_path, params: { practice_id: sibling.id }

    expect(response).to have_http_status(:forbidden)
  end
end
