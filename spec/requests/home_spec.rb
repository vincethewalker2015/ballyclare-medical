require "rails_helper"

RSpec.describe "Public landing page", type: :request do
  it "renders the root page without a staff account or sign in" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ballyclare Medical")
    expect(response.parsed_body.at_css("#hero-heading").text.squish).to eq("Care for every stage of life")
    expect(response.body).to include("Services")
    expect(response.body).to include("Our team")
    expect(response.body).to include("Book an appointment")
    expect(response.body).to include(guest_booking_path)
    expect(response.body).to include(new_user_session_path)
  end

  it "offers registered-patient signup separately from guest booking" do
    get root_path

    expect(response).to have_http_status(:ok)
    document = response.parsed_body
    expect(document.at_css('a[href="' + new_patient_account_registration_path + '"]')).to be_present
    expect(document.at_css('a[href="' + guest_booking_path + '"]')).to be_present
    expect(response.body).to include("Join a practice")
  end

  it "offers a working sign-in destination" do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
  end

  it "still requires authentication for practice appointments" do
    get practice_appointments_path

    expect(response).to redirect_to(new_user_session_path)
  end
end
