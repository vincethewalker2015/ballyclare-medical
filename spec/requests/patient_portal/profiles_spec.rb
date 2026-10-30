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
  it "requires confirmation when changing the sign-in email" do
    original_email = patient_account.email
    sign_in patient_account, scope: :patient_account
    patch patient_portal_profile_path, params: {
      patient_account: { email: "changed@example.com", current_password: "password123" }
    }
    expect(response).to redirect_to(patient_portal_profile_path)
    expect(patient_account.reload.email).to eq(original_email)
    expect(patient_account.unconfirmed_email).to eq("changed@example.com")
  end

  it "rejects a mismatched new password confirmation" do
    sign_in patient_account, scope: :patient_account
    patch patient_portal_profile_path, params: {
      patient_account: { email: patient_account.email, password: "newpassword123",
        password_confirmation: "differentpassword", current_password: "password123" }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(patient_account.reload.valid_password?("password123")).to be(true)
  end

  it "rejects an invalid email address" do
    sign_in patient_account, scope: :patient_account
    patch patient_portal_profile_path, params: {
      patient_account: { email: "not-an-email", current_password: "password123" }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "denies editing and updating when access is revoked" do
    patient_account.patient_account_links.update_all(status: "revoked")
    sign_in patient_account, scope: :patient_account
    get edit_patient_portal_profile_path
    expect(response).to have_http_status(:forbidden)
    patch patient_portal_profile_path, params: {
      patient_account: { email: "changed@example.com", current_password: "password123" }
    }
    expect(response).to have_http_status(:forbidden)
    expect(patient_account.reload.email).not_to eq("changed@example.com")
  end

  it "does not expose another patient's details" do
    other_patient = create(:patient, practice: practice, first_name: "PrivatePerson")
    sign_in patient_account, scope: :patient_account
    get patient_portal_profile_path
    expect(response.body).to include(patient.patient_number)
    expect(response.body).not_to include(other_patient.patient_number)
    expect(response.body).not_to include("PrivatePerson")
  end

end
