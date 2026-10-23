require "rails_helper"

RSpec.describe "Appointment patient search", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }
  let!(:membership) do
    create(:staff_member, practice: practice, user: user,
      staff_type: "administrator", access_level: "staff_admin")
  end

  before { sign_in user }

  it "renders the booking form with an empty searchable patient field" do
    get new_practice_appointment_path

    expect(response).to have_http_status(:success)
    page = response.parsed_body
    expect(page.at_css('input[name="patient_id"][type="hidden"]')["value"]).to be_blank
    expect(page.at_css("input#patient_search")["placeholder"]).to eq("Select patient")
    expect(page.at_css('select[name="patient_id"]')).to be_nil
  end

  it "returns at most five patients in alphabetical order" do
    7.times do |index|
      create(:patient, practice: practice, first_name: "Robin",
        last_name: "Search#{index}", patient_number: "SEARCH-#{index}")
    end

    get search_patients_practice_appointments_path, params: { q: "Robin" }

    expect(response).to have_http_status(:success)
    results = response.parsed_body
    expect(results.length).to eq(5)
    expect(results.map { |patient| patient["label"] }).to eq(
      (0..4).map { |index| "Search#{index}, Robin — SEARCH-#{index}" }
    )
  end

  it "finds patients by patient number" do
    patient = create(:patient, practice: practice, patient_number: "DEMO-P006",
      first_name: "Leo", last_name: "Anderson")

    get search_patients_practice_appointments_path, params: { q: "P006" }

    expect(response.parsed_body).to include(
      "id" => patient.id,
      "label" => "Anderson, Leo — DEMO-P006"
    )
  end

  it "never returns patients from another practice" do
    other_practice = create(:practice)
    create(:patient, practice: other_practice, first_name: "Private",
      last_name: "Person", patient_number: "OTHER-001")

    get search_patients_practice_appointments_path, params: { q: "Private" }

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to be_empty
  end

  it "rejects staff without operational access" do
    membership.update!(access_level: "staff")

    get search_patients_practice_appointments_path, params: { q: "Leo" }

    expect(response).to have_http_status(:forbidden)
  end

  it "requires authentication" do
    sign_out user

    get search_patients_practice_appointments_path, params: { q: "Leo" }

    expect(response).to redirect_to(new_user_session_path)
  end
end
