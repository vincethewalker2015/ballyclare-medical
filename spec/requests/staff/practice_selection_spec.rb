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

  def grant_sibling_membership(access_level: "staff_admin")
    create(:staff_member, user: user, practice: sibling,
      access_level: access_level, staff_type: "administrator")
  end

  it "defaults to the staff member's home practice" do
    get practice_patients_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("HomePatient")
    expect(response.body).not_to include("SiblingPatient")
  end

  it "switches to a sibling practice and scopes subsequent patient requests" do
    grant_sibling_membership
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

  it "rejects switching to a sibling without a local membership" do
    patch practice_selection_path, params: { practice_id: sibling.id }

    expect(response).to have_http_status(:forbidden)
    get practice_patients_path
    expect(response.body).to include("HomePatient")
    expect(response.body).not_to include("SiblingPatient")
  end

  it "rejects switching when the local membership is inactive" do
    local = grant_sibling_membership
    local.update!(active: false)

    patch practice_selection_path, params: { practice_id: sibling.id }

    expect(response).to have_http_status(:forbidden)
  end

  it "drops a previously selected practice when its local membership is deactivated" do
    local = grant_sibling_membership
    patch practice_selection_path, params: { practice_id: sibling.id }
    expect(response).to redirect_to(practice_appointments_path)

    local.update!(active: false)
    get practice_patients_path

    expect(response.body).to include("HomePatient")
    expect(response.body).not_to include("SiblingPatient")
  end

  describe "booking isolation after switching practices" do
    let!(:home_slot) { create(:appointment_slot, practice: home) }
    let!(:sibling_slot) { create(:appointment_slot, practice: sibling) }

    before do
      grant_sibling_membership
      patch practice_selection_path, params: { practice_id: sibling.id }
      expect(response).to redirect_to(practice_appointments_path)
    end

    it "rejects a patient from the home practice even with a valid selected-practice slot" do
      expect {
        post practice_appointments_path, params: {
          patient_id: home_patient.id,
          appointment_slot_id: sibling_slot.id
        }
      }.not_to change(Appointment, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "rejects a slot from the home practice even with a selected-practice patient" do
      expect {
        post practice_appointments_path, params: {
          patient_id: sibling_patient.id,
          appointment_slot_id: home_slot.id
        }
      }.not_to change(Appointment, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "rejects a patient from an unrelated medical group" do
      expect {
        post practice_appointments_path, params: {
          patient_id: outside_patient.id,
          appointment_slot_id: sibling_slot.id
        }
      }.not_to change(Appointment, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "does not expose the home practice appointment after switching" do
      home_appointment = create(:appointment, practice: home)

      get practice_appointment_path(home_appointment)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "selected-practice role boundaries" do
    it "does not carry home administrator privileges into a lower-privilege local membership" do
      grant_sibling_membership(access_level: "staff")
      patch practice_selection_path, params: { practice_id: sibling.id }
      expect(response).to redirect_to(practice_appointments_path)

      get new_practice_staff_member_path

      expect(response).to have_http_status(:forbidden)
    end

    it "uses the selected practice's senior administrator membership for privileged actions" do
      grant_sibling_membership(access_level: "senior_staff_admin")
      patch practice_selection_path, params: { practice_id: sibling.id }
      expect(response).to redirect_to(practice_appointments_path)

      get new_practice_staff_member_path

      expect(response).to have_http_status(:ok)
    end

    it "does not use an inactive local membership to elevate access" do
      create(:staff_member, user: user, practice: sibling, access_level: "senior_staff_admin",
        staff_type: "administrator", active: false)
      patch practice_selection_path, params: { practice_id: sibling.id }
      expect(response).to have_http_status(:forbidden)

      get new_practice_staff_member_path

      expect(response).to have_http_status(:ok)
    end
  end
end
