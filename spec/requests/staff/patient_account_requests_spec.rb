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

  it "does not complete an approved registration if email confirmation is missing" do
    membership.update!(access_level: "senior_staff_admin")
    account = create(:patient_account)
    request_record = PatientRegistrationRequest.create!(
      practice: practice,
      patient_account: account,
      review_status: "approved",
      patient_route: "new_patient",
      first_name: "Unconfirmed",
      last_name: "Applicant",
      date_of_birth: Date.new(1980, 1, 1),
      reviewed_by: membership,
      approved_by: membership,
      approved_at: Time.current,
      identity_verified_at: Time.current,
      verification_method: "in_person"
    )

    expect {
      CompletePatientRegistrationJob.perform_now(request_record.id)
    }.not_to change(Patient, :count)

    expect(PatientAccountLink.where(patient_account: account)).to be_empty
    expect(request_record.reload.review_status).to eq("approved")
  end

  it "links a verified existing patient only after senior approval without creating a duplicate patient" do
    membership.update!(access_level: "senior_staff_admin")
    account = create(:patient_account)
    account.confirm
    existing_patient = create(:patient, practice: practice)
    request_record = PatientRegistrationRequest.create!(
      practice: practice, patient_account: account
    )
    sign_in admin

    post verify_practice_patient_account_request_path(request_record),
      params: {
        patient_route: "existing_patient",
        patient_id: existing_patient.id,
        verification_method: "in_person",
        identity_checked: "1"
      }

    expect(request_record.reload.review_status).to eq("verified")
    expect(request_record.selected_patient).to eq(existing_patient)
    expect(PatientAccountLink.where(patient_account: account)).to be_empty

    post approve_practice_patient_account_request_path(request_record)
    expect(request_record.reload.review_status).to eq("approved")

    expect {
      CompletePatientRegistrationJob.perform_now(request_record.id)
      CompletePatientRegistrationJob.perform_now(request_record.id)
    }.not_to change(Patient, :count)

    link = PatientAccountLink.find_by!(patient_account: account)
    expect(link.patient).to eq(existing_patient)
    expect(link.practice).to eq(practice)
    expect(link.status).to eq("approved")
    expect(PatientAccountLink.where(patient_account: account).count).to eq(1)
    expect(request_record.reload.review_status).to eq("completed")
  end

  it "does not grant a second account access to an already linked patient" do
    membership.update!(access_level: "senior_staff_admin")
    existing_patient = create(:patient, practice: practice)
    original_account = create(:patient_account)
    original_account.confirm
    original_link = PatientAccountLink.create!(
      practice: practice,
      patient: existing_patient,
      patient_account: original_account,
      status: "approved",
      verified_by: membership,
      verification_method: "in_person",
      verified_at: Time.current,
      approved_at: Time.current
    )
    second_account = create(:patient_account)
    second_account.confirm
    request_record = PatientRegistrationRequest.create!(
      practice: practice,
      patient_account: second_account,
      review_status: "approved",
      patient_route: "existing_patient",
      selected_patient: existing_patient,
      reviewed_by: membership,
      approved_by: membership,
      approved_at: Time.current,
      identity_verified_at: Time.current,
      verification_method: "in_person"
    )

    expect {
      begin
        CompletePatientRegistrationJob.perform_now(request_record.id)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        # A rejected duplicate must not leave a partially completed registration.
      end
    }.not_to change(PatientAccountLink, :count)

    expect(original_link.reload).to have_attributes(
      patient: existing_patient,
      patient_account: original_account,
      status: "approved"
    )
    expect(PatientAccountLink.where(patient_account: second_account)).to be_empty
    expect(request_record.reload.review_status).not_to eq("completed")
  end

  it "handles a database uniqueness conflict after link prechecks" do
    membership.update!(access_level: "senior_staff_admin")
    account = create(:patient_account)
    account.confirm
    patient = create(:patient, practice: practice)
    request_record = PatientRegistrationRequest.create!(
      practice: practice, patient_account: account,
      review_status: "approved", patient_route: "existing_patient",
      selected_patient: patient, reviewed_by: membership,
      approved_by: membership, approved_at: Time.current,
      identity_verified_at: Time.current, verification_method: "in_person"
    )

    allow(PatientAccountLink).to receive(:create!)
      .and_raise(ActiveRecord::RecordNotUnique)

    expect {
      CompletePatientRegistrationJob.perform_now(request_record.id)
    }.not_to change(PatientAccountLink, :count)

    expect(request_record.reload.review_status).to eq("failed")
    expect(request_record.processed_at).to be_present
    expect(PatientAccountLink.where(patient_account: account)).to be_empty
  end

  it "records a failed registration when the selected patient is already linked" do
    membership.update!(access_level: "senior_staff_admin")
    existing_patient = create(:patient, practice: practice)
    original_account = create(:patient_account)
    original_account.confirm
    PatientAccountLink.create!(
      practice: practice, patient: existing_patient,
      patient_account: original_account, status: "approved",
      verified_by: membership, verification_method: "in_person",
      verified_at: Time.current, approved_at: Time.current
    )

    second_account = create(:patient_account)
    second_account.confirm
    request_record = PatientRegistrationRequest.create!(
      practice: practice, patient_account: second_account,
      review_status: "approved", patient_route: "existing_patient",
      selected_patient: existing_patient, reviewed_by: membership,
      approved_by: membership, approved_at: Time.current,
      identity_verified_at: Time.current, verification_method: "in_person"
    )

    expect {
      CompletePatientRegistrationJob.perform_now(request_record.id)
    }.not_to change(PatientAccountLink, :count)

    expect(request_record.reload.review_status).to eq("failed")
    expect(PatientAccountLink.find_by(patient_account: second_account)).to be_nil
    expect(PatientAccountLink.find_by!(patient_account: original_account).patient)
      .to eq(existing_patient)
  end

  it "does not provide a route for creating an assignment" do
    sign_in admin
    expect {
      post "/practice/patient_account_requests", params: { email: "test@example.com" }
    }.not_to change(PatientAccountLink, :count)

    expect(response).to have_http_status(:not_found)
  end
end
