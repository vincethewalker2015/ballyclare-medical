require "rails_helper"

RSpec.describe "Practice staff members", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }

  before do
    create(:staff_member, practice: practice, user: user, staff_type: "administrator")
  end

  describe "GET /practice/staff_members" do
    it "lists staff from the signed-in staff member's practice only" do
      create(
        :staff_member,
        practice: practice,
        first_name: "Local",
        last_name: "Clinician",
        staff_type: "doctor"
      )
      create(
        :staff_member,
        practice: create(:practice),
        first_name: "Foreign",
        last_name: "Clinician",
        staff_type: "nurse"
      )
      sign_in user

      get practice_staff_members_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Local Clinician")
      expect(response.body).not_to include("Foreign Clinician")
    end

    it "redirects visitors who are not signed in" do
      get practice_staff_members_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "forbids signed-in users without a staff record" do
      sign_in create(:user)

      get practice_staff_members_path

      expect(response).to have_http_status(:forbidden)
    end
  end
end
