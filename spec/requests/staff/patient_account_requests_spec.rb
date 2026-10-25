require "rails_helper"

RSpec.describe "Patient account requests", type: :request do
  let(:practice) { create(:practice) }
  let(:admin) { create(:user) }
  let!(:membership) do
    create(:staff_member, practice: practice, user: admin,
      active: true, access_level: "staff_admin")
  end

  it "requires staff authentication" do
    get practice_patient_account_requests_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "rejects basic staff access" do
    membership.update!(access_level: "staff")
    sign_in admin
    get practice_patient_account_requests_path
    expect(response).to have_http_status(:forbidden)
  end

  it "does not expose unassigned account registrations" do
    account = create(:patient_account)
    account.confirm

    sign_in admin
    get practice_patient_account_requests_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(account.email)
  end

  it "shows confirmed registration requests only for the current practice" do
    own_account = create(:patient_account)
    own_account.confirm
    PatientRegistrationRequest.create!(practice: practice, patient_account: own_account)

    other_account = create(:patient_account)
    other_account.confirm
    PatientRegistrationRequest.create!(practice: create(:practice), patient_account: other_account)

    unconfirmed_account = create(:patient_account)
    PatientRegistrationRequest.create!(practice: practice, patient_account: unconfirmed_account)

    sign_in admin
    get practice_patient_account_requests_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_account.email)
    expect(response.body).not_to include(other_account.email)
    expect(response.body).not_to include(unconfirmed_account.email)
  end

  it "lets a practice administrator review a confirmed request without granting access" do
    account = create(:patient_account)
    account.confirm
    request = PatientRegistrationRequest.create!(practice: practice, patient_account: account)

    sign_in admin
    get practice_patient_account_request_path(request)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(account.email)
    expect(response.body).to include("Identity verification")
    expect(PatientAccountLink.count).to eq(0)
  end

  it "prevents viewing another practice's registration request" do
    account = create(:patient_account)
    account.confirm
    request = PatientRegistrationRequest.create!(
      practice: create(:practice), patient_account: account
    )

    sign_in admin
    get practice_patient_account_request_path(request)

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(account.email)
  end

  it "prevents basic staff from viewing registration details" do
    account = create(:patient_account)
    account.confirm
    request = PatientRegistrationRequest.create!(practice: practice, patient_account: account)

    membership.update!(access_level: "staff")
    sign_in admin
    get practice_patient_account_request_path(request)

    expect(response).to have_http_status(:forbidden)
  end

  it "searches only the current practice's patients by name or patient number" do
    account = create(:patient_account)
    account.confirm
    request_record = PatientRegistrationRequest.create!(practice: practice, patient_account: account)
    own_patient = create(:patient, practice: practice, first_name: "Distinctive")
    other_patient = create(:patient, practice: create(:practice), first_name: "Distinctive")
    sign_in admin

    get practice_patient_account_request_path(request_record), params: { patient_search: "Distinctive" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_patient.patient_number)
    expect(response.body).not_to include(other_patient.patient_number)
    expect(response.body).to include("Record identity verification")
  end

  it "does not display the full patient directory before a search" do
    account = create(:patient_account)
    account.confirm
    request_record = PatientRegistrationRequest.create!(practice: practice, patient_account: account)
    patient = create(:patient, practice: practice)
    sign_in admin

    get practice_patient_account_request_path(request_record)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(patient.patient_number)
  end

  it "records verification without approving a patient link" do
    account = create(:patient_account)
    account.confirm
    request_record = PatientRegistrationRequest.create!(practice: practice, patient_account: account)
    patient = create(:patient, practice: practice)
    sign_in admin

    expect {
      post verify_practice_patient_account_request_path(request_record),
        params: { patient_id: patient.id, verification_method: "in_person", identity_checked: "1" }
    }.to change(PatientAccountLink, :count).by(1)
      .and change(AuditEvent, :count).by(1)

    link = PatientAccountLink.last
    expect(link.status).to eq("pending")
    expect(link.approved_at).to be_nil
    expect(link.verified_by).to eq(membership)
  end

  it "rejects a patient from another practice" do
    account = create(:patient_account)
    account.confirm
    request_record = PatientRegistrationRequest.create!(practice: practice, patient_account: account)
    sign_in admin

    expect {
      post verify_practice_patient_account_request_path(request_record),
        params: { patient_id: create(:patient).id, verification_method: "in_person",
                  identity_checked: "1" }
    }.not_to change(PatientAccountLink, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "rejects verification without explicit identity attestation" do
    account = create(:patient_account)
    account.confirm
    request_record = PatientRegistrationRequest.create!(practice: practice, patient_account: account)
    sign_in admin

    expect {
      post verify_practice_patient_account_request_path(request_record),
        params: { patient_id: create(:patient, practice: practice).id,
                  verification_method: "in_person" }
    }.not_to change(PatientAccountLink, :count)
  end

  it "does not provide a route for creating an assignment" do
    sign_in admin
    expect {
      post "/practice/patient_account_requests", params: { email: "test@example.com" }
    }.not_to change(PatientAccountLink, :count)

    expect(response).to have_http_status(:not_found)
  end
end
