require "rails_helper"

RSpec.describe "Patient portal profile", type: :request do
  let(:practice) { create(:practice) }
  let(:patient) { create(:patient, practice: practice) }
  let(:patient_account) { create(:patient_account, confirmed_at: Time.current) }

  before do
    PatientAccountLink.create!(
      patient_account: patient_account, patient: patient, practice: practice,
      status: "approved", approved_at: Time.current, verified_at: Time.current,
      verification_method: "in_person",
      verified_by: create(:staff_member, practice: practice, access_level: "staff_admin")
    )
  end

  it "requires sign-in" do
    get patient_portal_profile_path
    expect(response).to redirect_to(new_patient_account_session_path)
  end

  it "shows verified patient details" do
    sign_in patient_account, scope: :patient_account
    get patient_portal_profile_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(patient.patient_number)
  end

  it "requires the current password to update sign-in email" do
    sign_in patient_account, scope: :patient_account
    patch patient_portal_profile_path, params: {
      patient_account: { email: "new@example.com", current_password: "incorrect" }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(patient_account.reload.email).not_to eq("new@example.com")
  end

  it "updates the password when the current password is correct" do
    sign_in patient_account, scope: :patient_account
    patch patient_portal_profile_path, params: {
      patient_account: { email: patient_account.email, password: "newpassword123",
        password_confirmation: "newpassword123", current_password: "password123" }
    }
    expect(response).to redirect_to(patient_portal_profile_path)
    expect(patient_account.reload.valid_password?("newpassword123")).to be(true)
  end

  it "does not permit changes to verified identity fields" do
    sign_in patient_account, scope: :patient_account
    patch patient_portal_profile_path, params: {
      patient_account: { email: patient_account.email, current_password: "password123",
        first_name: "Changed", date_of_birth: "2000-01-01" }
    }
    expect(patient.reload.first_name).to eq("Jane")
    expect(patient.date_of_birth).to eq(Date.new(1990, 1, 1))
  end

  it "denies profile access when approval is revoked" do
    patient_account.patient_account_links.update_all(status: "revoked")
    sign_in patient_account, scope: :patient_account
    get patient_portal_profile_path
    expect(response).to have_http_status(:forbidden)
  end
end
