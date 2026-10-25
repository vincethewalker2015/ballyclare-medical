require "rails_helper"

RSpec.describe "Patient account authentication", type: :request do
  let(:password) { "SecurePassword123!" }

  it "shows a separate patient registration page" do
    get new_patient_account_registration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Create your patient account")
  end

  it "registers an unconfirmed account without creating a patient record" do
    expect {
      post patient_account_registration_path, params: {
        patient_account: {
          email: "newpatient@example.com",
          password: password,
          password_confirmation: password
        }
      }
    }.to change(PatientAccount, :count).by(1).and change(Patient, :count).by(0)

    expect(PatientAccount.last).not_to be_confirmed
    expect(response).to have_http_status(:redirect)
  end

  it "rejects invalid registration details" do
    post patient_account_registration_path, params: {
      patient_account: {
        email: "invalid",
        password: password,
        password_confirmation: "different"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(PatientAccount.count).to eq(0)
  end

  it "does not allow an unconfirmed patient account to sign in" do
    account = create(:patient_account, password: password)

    post patient_account_session_path, params: {
      patient_account: { email: account.email, password: password }
    }

    expect(response).not_to redirect_to(patient_portal_path)
  end

  it "allows a confirmed patient account to access only its unlinked landing page" do
    account = create(:patient_account, password: password)
    account.confirm

    post patient_account_session_path, params: {
      patient_account: { email: account.email, password: password }
    }

    expect(response).to redirect_to(patient_portal_path)
    follow_redirect!
    expect(response.body).to include("not yet linked to a medical record")

    get practice_patients_path
    expect(response).not_to have_http_status(:ok)
  end

  it "requires patient authentication for the patient portal" do
    get patient_portal_path

    expect(response).to redirect_to(new_patient_account_session_path)
  end

  it "keeps staff login separate from patient login" do
    user = create(:user, password: password)
    create(:staff_member, user: user, active: true)

    post patient_account_session_path, params: {
      patient_account: { email: user.email, password: password }
    }

    expect(response).not_to redirect_to(patient_portal_path)
  end
end
