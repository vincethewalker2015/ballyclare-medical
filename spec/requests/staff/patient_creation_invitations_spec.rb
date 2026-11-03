require "rails_helper"

RSpec.describe "Staff patient creation and portal invitations", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }
  let!(:staff) do
    create(:staff_member, practice: practice, user: user,
      staff_type: "administrator", access_level: "staff_admin", active: true)
  end
  let(:details) { { first_name: "Jamie", last_name: "Taylor", date_of_birth: "1990-01-01" } }

  before { sign_in user }

  def activation_emails
    ActionMailer::Base.deliveries.select { |mail| mail.subject.include?("Activate your patient portal") }
  end

  it "creates a practice patient without requiring a portal account" do
    expect { post practice_patients_path, params: { patient: details } }
      .to change(Patient, :count).by(1)
    expect(PatientAccount.count).to eq(0)
    expect(PatientAccountLink.count).to eq(0)
  end

  it "reuses the registration request workflow when inviting a newly created patient" do
    expect {
      post practice_patients_path, params: {
        patient: details.merge(invite_to_portal: "1", email: "new.patient@example.com")
      }
    }.to change(Patient, :count).by(1)
      .and change(PatientAccount, :count).by(1)
      .and change(PatientRegistrationRequest, :count).by(1)

    patient = Patient.last
    account = PatientAccount.last
    request = PatientRegistrationRequest.last
    expect(request).to have_attributes(practice: practice, patient_account: account,
      first_name: patient.first_name, last_name: patient.last_name,
      date_of_birth: patient.date_of_birth, review_status: "awaiting_review")
    expect(account).not_to be_confirmed
    expect(activation_emails.length).to eq(1)
    expect(ActionMailer::Base.deliveries.count { |mail| mail.to.include?(account.email) }).to eq(1)
    expect(activation_emails.first.html_part.body.decoded).to include("Confirm email address and set password")
    expect(activation_emails.first.html_part.body.decoded).to include("/patients/confirmation", "reset_password_token=")
    expect(PatientAccountLink.count).to eq(0)
    expect(response).to redirect_to(practice_patient_path(patient))
  end

  it "does not create a patient if the requested portal email is already registered" do
    create(:patient_account, email: "taken@example.com")
    expect {
      post practice_patients_path, params: {
        patient: details.merge(invite_to_portal: "1", email: "taken@example.com")
      }
    }.not_to change(Patient, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(PatientRegistrationRequest.count).to eq(0)
  end

  it "does not allow non-administrators to issue invitations" do
    staff.update!(staff_type: "doctor", access_level: "staff_clinician")
    expect {
      post practice_patients_path, params: {
        patient: details.merge(invite_to_portal: "1", email: "new.patient@example.com")
      }
    }.not_to change(Patient, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "invites an existing patient without creating a second clinical record or granting access" do
    patient = create(:patient, practice: practice)
    expect {
      post practice_patient_portal_invitation_path(patient), params: { email: "existing@example.com" }
    }.to change(PatientRegistrationRequest, :count).by(1)
    expect(Patient.count).to eq(1)
    expect(PatientAccountLink.count).to eq(0)
    expect(PatientRegistrationRequest.last.review_status).to eq("awaiting_review")
    expect(activation_emails.length).to eq(1)
    expect(ActionMailer::Base.deliveries.count { |mail| mail.to.include?("existing@example.com") }).to eq(1)
  end

  it "cannot invite a patient belonging to another practice" do
    patient = create(:patient, practice: create(:practice))
    expect {
      post practice_patient_portal_invitation_path(patient), params: { email: "other@example.com" }
    }.not_to change(PatientAccount, :count)
    expect(response).to have_http_status(:not_found)
  end
end
