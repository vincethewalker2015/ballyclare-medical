require "rails_helper"

RSpec.describe "Staff medical group isolation", type: :request do
  let(:practice_a) { create(:practice) }
  let(:practice_b) { create(:practice) }
  let(:user) { create(:user) }
  let!(:staff_member) do
    create(:staff_member, practice: practice_a, user: user, access_level: "staff_admin")
  end
  let!(:patient_a) { create(:patient, practice: practice_a, first_name: "Alice", last_name: "Local") }
  let!(:patient_b) { create(:patient, practice: practice_b, first_name: "Bob", last_name: "External") }

  before { sign_in user }

  it "keeps the two practices in distinct medical groups" do
    expect(practice_a.medical_group_id).not_to eq(practice_b.medical_group_id)
    expect(staff_member.practice.medical_group_id).to eq(practice_a.medical_group_id)
  end

  it "does not show another group's patients in the staff patient list" do
    get practice_patients_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Alice")
    expect(response.body).not_to include("Bob")
  end

  it "does not return another group's patients through staff search" do
    get practice_patients_path, params: { patient_search: "External" }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Bob")
  end

  it "does not expose another group's patient detail" do
    expect {
      get practice_patient_path(patient_b)
    }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "does not allow updating another group's patient" do
    expect {
      patch practice_patient_path(patient_b), params: {
        patient: { first_name: "Changed" }
      }
    }.to raise_error(ActiveRecord::RecordNotFound)

    expect(patient_b.reload.first_name).to eq("Bob")
  end

  it "does not allow editing another group's patient" do
    expect {
      get edit_practice_patient_path(patient_b)
    }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
