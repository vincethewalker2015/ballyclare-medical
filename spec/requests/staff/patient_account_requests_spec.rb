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

  it "shows only pending links belonging to the signed-in practice" do
    account = create(:patient_account)
    account.confirm
    patient = create(:patient, practice: practice)
    link = PatientAccountLink.create!(
      practice: practice, patient: patient, patient_account: account
    )

    other_practice = create(:practice)
    other_account = create(:patient_account)
    other_account.confirm
    PatientAccountLink.create!(
      practice: other_practice,
      patient: create(:patient, practice: other_practice),
      patient_account: other_account
    )

    sign_in admin
    get practice_patient_account_requests_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(link.patient_account.email)
    expect(response.body).not_to include(other_account.email)
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

  it "does not provide a route for creating an assignment" do
    sign_in admin
    expect {
      post "/practice/patient_account_requests", params: { email: "test@example.com" }
    }.not_to change(PatientAccountLink, :count)

    expect(response).to have_http_status(:not_found)
  end
end
