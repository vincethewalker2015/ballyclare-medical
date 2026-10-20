require "rails_helper"

RSpec.describe "Practice navigation permissions", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }
  let!(:staff_member) do
    create(:staff_member, practice: practice, user: user,
      staff_type: "administrator", access_level: "staff")
  end

  before { sign_in user }

  it "shows read-only diary navigation but hides operational tools from basic staff" do
    get practice_staff_members_path

    expect(response).to have_http_status(:success)
    navigation = response.parsed_body.at_css('nav[aria-label="Practice navigation"]')
    expect(navigation).to be_present
    expect(navigation.css("a").map { |link| link["href"] }).not_to include(
      practice_availability_blocks_path,
      practice_patients_path
    )
    expect(navigation.css("a").map { |link| link["href"] }).to include(
      practice_staff_members_path, user_manual_path, practice_appointments_path
    )
    expect(response.parsed_body.at_css("header a")["href"]).to eq(practice_appointments_path)
  end

  %w[staff_admin senior_staff_admin staff_clinician].each do |role|
    it "shows operational navigation for #{role}" do
      attributes = { access_level: role }
      attributes[:staff_type] = "doctor" if role == "staff_clinician"
      staff_member.update!(attributes)

      get practice_staff_members_path

      expect(response).to have_http_status(:success)
      links = response.parsed_body.at_css('nav[aria-label="Practice navigation"]')
        .css("a").map { |link| link["href"] }
      expect(links).to include(
        practice_appointments_path,
        practice_availability_blocks_path,
        practice_patients_path
      )
      expect(response.parsed_body.at_css("header a")["href"]).to eq(practice_appointments_path)
    end
  end
end
