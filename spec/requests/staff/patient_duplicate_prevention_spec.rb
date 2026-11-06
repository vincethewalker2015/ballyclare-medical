require "rails_helper"

RSpec.describe "Staff patient duplicate prevention", type: :request do
  let(:practice) { create(:practice) }
  let(:admin) { create(:user) }
  let!(:membership) do
    create(:staff_member, practice: practice, user: admin,
      staff_type: "administrator", access_level: "senior_staff_admin", active: true)
  end
  let(:details) do
    { first_name: "Morgan", last_name: "Price", date_of_birth: Date.new(1985, 6, 9) }
  end

  before { sign_in admin }

  def registration_request
    account = create(:patient_account)
    account.confirm
    PatientRegistrationRequest.create!(
      practice: practice, patient_account: account, **details
    )
  end

  it "warns about possible existing patients and blocks the new-patient verification route" do
    existing = create(:patient, practice: practice, **details)
    request_record = registration_request

    get practice_patient_account_request_path(request_record)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(existing.patient_number)
    expect(response.body).to include("A possible existing patient was found")

    document = Nokogiri::HTML(response.body)
    new_option = document.at_css('input[name="patient_route"][value="new_patient"]')
    expect(new_option).to be_present
    expect(new_option["disabled"]).to be_present

    post verify_practice_patient_account_request_path(request_record),
      params: { patient_route: "new_patient", verification_method: "in_person",
                identity_checked: "1" }

    expect(response).to redirect_to(practice_patient_account_request_path(request_record))
    expect(request_record.reload.review_status).to eq("awaiting_review")
    expect(PatientAccountLink.where(patient_account: request_record.patient_account)).to be_empty

    post verify_practice_patient_account_request_path(request_record),
      params: { patient_route: "existing_patient", patient_id: existing.id,
                verification_method: "in_person", identity_checked: "1" }

    expect(request_record.reload.review_status).to eq("verified")
    expect(request_record.selected_patient).to eq(existing)
  end

  it "rejects new-patient approval when a matching record appears after verification" do
    request_record = registration_request

    post verify_practice_patient_account_request_path(request_record),
      params: { patient_route: "new_patient", verification_method: "in_person",
                identity_checked: "1" }
    expect(request_record.reload.review_status).to eq("verified")

    create(:patient, practice: practice, **details)

    expect {
      post approve_practice_patient_account_request_path(request_record)
    }.not_to have_enqueued_job(CompletePatientRegistrationJob)

    expect(response).to redirect_to(practice_patient_account_request_path(request_record))
    expect(request_record.reload.review_status).to eq("verified")
  end

  it "blocks an approved registration in the job when another matching patient exists" do
    account = create(:patient_account)
    account.confirm
    request_record = PatientRegistrationRequest.create!(
      practice: practice, patient_account: account, **details,
      review_status: "approved", patient_route: "new_patient",
      reviewed_by: membership, approved_by: membership,
      verification_method: "in_person",
      identity_verified_at: Time.current, approved_at: Time.current
    )
    existing = create(:patient, practice: practice, **details)

    expect {
      CompletePatientRegistrationJob.perform_now(request_record.id)
    }.not_to change(Patient, :count)
    expect(PatientAccountLink.where(patient_account: account)).to be_empty
    expect(request_record.reload.review_status).to eq("failed")
    expect(request_record.selected_patient_id).to be_nil
    expect(Patient.find(existing.id)).to be_present

    expect {
      CompletePatientRegistrationJob.perform_now(request_record.id)
    }.not_to change(Patient, :count)
  end

  it "rejects direct staff creation of a possible duplicate and creates no portal invitation" do
    existing = create(:patient, practice: practice, **details)

    expect {
      post practice_patients_path,
        params: { patient: details.merge(first_name: " mOrGaN ",
          last_name: "PRICE", invite_to_portal: "1", email: "duplicate@example.test") }
    }.not_to change(Patient, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("A possible existing patient has the same name and date of birth")
    expect(PatientAccount.where(email: "duplicate@example.test")).to be_empty
    expect(PatientRegistrationRequest.where(first_name: " mOrGaN ")).to be_empty
    expect(existing.reload.patient_number).to be_present
  end

  it "does not treat matching patients in another practice as duplicates" do
    create(:patient, practice: create(:practice), **details)

    expect {
      post practice_patients_path, params: { patient: details }
    }.to change(Patient.where(practice: practice), :count).by(1)

    expect(response).to redirect_to(practice_patients_path)
  end
end
