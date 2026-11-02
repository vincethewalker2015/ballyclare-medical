require "rails_helper"

RSpec.describe "Staff appointment roles after practice switching", type: :request do
  let(:group) { create(:medical_group) }
  let(:home) { create(:practice, medical_group: group) }
  let(:sibling) { create(:practice, medical_group: group) }
  let(:outsider) { create(:practice) }
  let(:user) { create(:user) }
  let!(:sibling_appointment) { create(:appointment, practice: sibling) }
  let!(:outsider_appointment) { create(:appointment, practice: outsider) }

  context "when signed in as an administrator" do
    before do
      create(:staff_member, user: user, practice: home, access_level: "staff_admin")
      create(:staff_member, user: user, practice: sibling, access_level: "staff_admin")
      sign_in user
      patch practice_selection_path, params: { practice_id: sibling.id }
      expect(response).to redirect_to(practice_appointments_path)
    end

    it "can view an appointment belonging to the selected sibling practice" do
      get practice_appointment_path(sibling_appointment)

      expect(response).to have_http_status(:ok)
    end

    it "cannot view an appointment from an unrelated medical group" do
      get practice_appointment_path(outsider_appointment)

      expect(response).to have_http_status(:not_found)
    end
  end

  context "when signed in as a clinician" do
    before do
      create(:staff_member, user: user, practice: home, access_level: "staff_clinician", staff_type: "doctor")
      sign_in user
      patch practice_selection_path, params: { practice_id: sibling.id }
      expect(response).to have_http_status(:forbidden)
    end

    it "cannot view another clinician's appointment at the selected sibling practice" do
      get practice_appointment_path(sibling_appointment)

      expect(response).to have_http_status(:forbidden)
    end

    it "cannot change another clinician's appointment status" do
      expect {
        patch status_practice_appointment_path(sibling_appointment), params: { status: "confirmed" }
      }.not_to change { sibling_appointment.reload.status }

      expect(response).to have_http_status(:not_found)
    end

    it "cannot view appointments from an unrelated medical group" do
      get practice_appointment_path(outsider_appointment)

      expect(response).to have_http_status(:not_found)
    end
  end

  context "when a clinician also has a membership at the sibling practice" do
    let!(:home_membership) do
      create(:staff_member, user: user, practice: home, access_level: "staff_clinician", staff_type: "doctor")
    end
    let!(:sibling_membership) do
      create(:staff_member, user: user, practice: sibling, access_level: "staff_clinician", staff_type: "doctor")
    end
    let!(:own_sibling_appointment) do
      create(:appointment, practice: sibling, clinician: sibling_membership)
    end

    before do
      sign_in user
      patch practice_selection_path, params: { practice_id: sibling.id }
      expect(response).to redirect_to(practice_appointments_path)
    end

    it "shows the clinician's own appointment at the selected practice" do
      get practice_appointment_path(own_sibling_appointment)

      expect(response).to have_http_status(:ok)
    end

    it "still forbids a different clinician's appointment" do
      get practice_appointment_path(sibling_appointment)

      expect(response).to have_http_status(:forbidden)
    end

    it "filters the diary to the selected practice's clinician identity" do
      get practice_appointments_path, params: { view: "upcoming", layout: "list" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(sibling_appointment.id)
    end
  end

  context "when a clinician has no membership at the sibling practice" do
    before do
      create(:staff_member, user: user, practice: home, access_level: "staff_clinician", staff_type: "doctor")
      sign_in user
      patch practice_selection_path, params: { practice_id: sibling.id }
      expect(response).to have_http_status(:forbidden)
    end

    it "renders an empty clinician diary instead of exposing all clinicians" do
      get practice_appointments_path, params: { view: "upcoming", layout: "list" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(sibling_appointment.id)
    end
  end
end
