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

    it "rejects invalid patient details without creating a record" do
      sign_in user

      expect {
        post practice_patients_path, params: {
          patient: {
            patient_number: "INVALID-001",
            first_name: "",
            last_name: "Jones",
            date_of_birth: "1992-04-17"
          }
        }
      }.not_to change(Patient, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("First name")
    end

    it "rejects duplicate patient numbers within the same practice" do
      create(:patient, practice: practice, patient_number: "EXISTING-001")
      sign_in user

      expect {
        post practice_patients_path, params: {
          patient: {
            patient_number: "EXISTING-001",
            first_name: "Alice",
            last_name: "Jones",
            date_of_birth: "1992-04-17"
          }
        }
      }.not_to change(Patient, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Patient number has already been taken")
    end

    it "ignores a submitted practice id and assigns the current practice" do
      other_practice = create(:practice)
      sign_in user

      expect {
        post practice_patients_path, params: {
          patient: {
            practice_id: other_practice.id,
            patient_number: "SECURE-001",
            first_name: "Alice",
            last_name: "Jones",
            date_of_birth: "1992-04-17"
          }
        }
      }.to change(practice.patients, :count).by(1)

      expect(other_practice.patients.where(patient_number: "SECURE-001")).to be_empty
    end
  end
  describe "GET /practice/patients/:id" do
    it "shows a patient from the current practice" do
      patient = create(:patient, practice: practice, first_name: "Alice", last_name: "Jones")
      sign_in user

      get practice_patient_path(patient)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Alice", "Jones", patient.patient_number)
    end

    it "does not show a patient from another practice" do
      foreign_patient = create(:patient, practice: create(:practice))
      sign_in user

      get practice_patient_path(foreign_patient)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /practice/patients/:id/edit" do
    it "shows the edit form for a patient in the current practice" do
      patient = create(:patient, practice: practice)
      sign_in user

      get edit_practice_patient_path(patient)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Edit patient")
    end
  end

  describe "PATCH /practice/patients/:id" do
    it "updates a patient in the current practice" do
      patient = create(:patient, practice: practice)
      sign_in user

      patch practice_patient_path(patient), params: {
        patient: { first_name: "Updated", last_name: "Name" }
      }

      expect(response).to redirect_to(practice_patient_path(patient))
      expect(patient.reload).to have_attributes(first_name: "Updated", last_name: "Name")
    end

    it "does not update a patient from another practice" do
      foreign_patient = create(:patient, practice: create(:practice), first_name: "Original")
      sign_in user

      patch practice_patient_path(foreign_patient), params: {
        patient: { first_name: "Changed" }
      }

      expect(response).to have_http_status(:not_found)
      expect(foreign_patient.reload.first_name).to eq("Original")
    end
  end
end
