require "rails_helper"

RSpec.describe "Practice patients", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }

  before do
    create(:staff_member, practice: practice, user: user, staff_type: "administrator")
  end

  describe "GET /practice/patients" do
    it "lists patients from the signed-in staff member's practice only" do
      own_patient = create(
        :patient,
        practice: practice,
        first_name: "Local",
        last_name: "Patient"
      )
      other_patient = create(
        :patient,
        practice: create(:practice),
        first_name: "Foreign",
        last_name: "Patient"
      )
      sign_in user

      get practice_patients_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(own_patient.first_name, own_patient.last_name)
      expect(response.body).not_to include(other_patient.first_name, other_patient.last_name)
    end

    it "redirects visitors who are not signed in" do
      get practice_patients_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "forbids signed-in users who are not staff members" do
      sign_in create(:user)

      get practice_patients_path

      expect(response).to have_http_status(:forbidden)
    end
  end
end
