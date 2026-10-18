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
      expect(response.body).not_to include(other_patient.first_name)
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
  describe "GET /practice/patients/new" do
    it "shows the new patient form to staff" do
      sign_in user

      get new_practice_patient_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("New patient")
    end
  end

  describe "POST /practice/patients" do
    it "creates a patient belonging to the signed-in staff member's practice" do
      sign_in user

      expect {
        post practice_patients_path, params: {
          patient: {
            patient_number: "NEW-001",
            first_name: "Alice",
            last_name: "Jones",
            date_of_birth: "1992-04-17"
          }
        }
      }.to change(practice.patients, :count).by(1)

      patient = practice.patients.find_by!(patient_number: "NEW-001")
      expect(patient).to have_attributes(
        first_name: "Alice",
        last_name: "Jones",
        date_of_birth: Date.new(1992, 4, 17)
      )
      expect(response).to redirect_to(practice_patients_path)
    end
  end
end
