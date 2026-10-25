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

  it "records new-patient verification without creating a clinical record" do
    account = create(:patient_account)
    account.confirm
    request_record = PatientRegistrationRequest.create!(
      practice: practice, patient_account: account,
      first_name: "Vincent", last_name: "Walker", date_of_birth: Date.new(1980, 1, 1)
    )
    sign_in admin

    expect {
      post verify_practice_patient_account_request_path(request_record),
        params: { patient_route: "new_patient", verification_method: "in_person",
                  identity_checked: "1" }
    }.to change(AuditEvent, :count).by(1)

    expect(request_record.reload.review_status).to eq("verified")
    expect(PatientAccountLink.count).to eq(0)
    expect(Patient.count).to eq(0)
  end

  it "rejects an existing patient from another practice" do
    account = create(:patient_account)
    account.confirm
    request_record = PatientRegistrationRequest.create!(practice: practice, patient_account: account)
    sign_in admin

    post verify_practice_patient_account_request_path(request_record),
      params: { patient_route: "existing_patient", patient_id: create(:patient).id,
                verification_method: "in_person", identity_checked: "1" }

    expect(response).to have_http_status(:not_found)
    expect(request_record.reload.review_status).to eq("awaiting_review")
  end

  it "rejects verification without identity attestation" do
    account = create(:patient_account)
    account.confirm
    request_record = PatientRegistrationRequest.create!(practice: practice, patient_account: account)
    sign_in admin

    post verify_practice_patient_account_request_path(request_record),
      params: { patient_route: "existing_patient",
                patient_id: create(:patient, practice: practice).id,
                verification_method: "in_person" }

    expect(request_record.reload.review_status).to eq("awaiting_review")
  end

  it "prevents staff admins from approving verified requests" do
    account = create(:patient_account)
    account.confirm
    request_record = PatientRegistrationRequest.create!(
      practice: practice, patient_account: account, review_status: "verified",
      patient_route: "new_patient", first_name: "Vincent", last_name: "Walker",
      date_of_birth: Date.new(1980, 1, 1), reviewed_by: membership,
      identity_verified_at: Time.current, verification_method: "in_person"
    )
    sign_in admin

    post approve_practice_patient_account_request_path(request_record)

    expect(response).to have_http_status(:forbidden)
    expect(request_record.reload.review_status).to eq("verified")
  end

  it "queues senior approval and completes the registration exactly once" do
    membership.update!(access_level: "senior_staff_admin")
    account = create(:patient_account)
    account.confirm
    request_record = PatientRegistrationRequest.create!(
      practice: practice, patient_account: account,
      first_name: "Vincent", last_name: "Walker", date_of_birth: Date.new(1980, 1, 1)
    )
    sign_in admin
    post verify_practice_patient_account_request_path(request_record),
      params: { patient_route: "new_patient", verification_method: "in_person",
                identity_checked: "1" }

    expect {
      post approve_practice_patient_account_request_path(request_record)
    }.to have_enqueued_job(CompletePatientRegistrationJob).with(request_record.id)

    expect(request_record.reload.review_status).to eq("approved")
    expect {
      CompletePatientRegistrationJob.perform_now(request_record.id)
      CompletePatientRegistrationJob.perform_now(request_record.id)
    }.to change(Patient, :count).by(1).and change(PatientAccountLink, :count).by(1)

    expect(request_record.reload.review_status).to eq("completed")
    expect(PatientAccountLink.last.status).to eq("approved")
    get practice_patient_account_request_path(request_record)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PatientAccountLink.last.patient.patient_number)
    expect(response.body).to include(practice_patient_path(PatientAccountLink.last.patient))

  end

  it "does not provide a route for creating an assignment" do
    sign_in admin
    expect {
      post "/practice/patient_account_requests", params: { email: "test@example.com" }
    }.not_to change(PatientAccountLink, :count)

    expect(response).to have_http_status(:not_found)
  end
end
