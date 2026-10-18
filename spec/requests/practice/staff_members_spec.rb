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
  describe "PATCH /practice/staff_members/:id/access_level" do
    let(:target) { create(:staff_member, practice: practice, access_level: "staff") }

    it "allows a senior staff admin to assign staff admin access" do
      user.staff_members.find_by!(practice: practice).update!(
        access_level: "senior_staff_admin"
      )
      sign_in user

      patch access_level_practice_staff_member_path(target), params: {
        staff_member: { access_level: "staff_admin" }
      }

      expect(response).to redirect_to(practice_staff_members_path)
      expect(target.reload.access_level).to eq("staff_admin")
    end

    it "forbids ordinary staff from changing access levels" do
      sign_in user

      patch access_level_practice_staff_member_path(target), params: {
        staff_member: { access_level: "senior_staff_admin" }
      }

      expect(response).to have_http_status(:forbidden)
      expect(target.reload.access_level).to eq("staff")
    end

    it "forbids staff admins from changing access levels" do
      user.staff_members.find_by!(practice: practice).update!(
        access_level: "staff_admin"
      )
      sign_in user

      patch access_level_practice_staff_member_path(target), params: {
        staff_member: { access_level: "senior_staff_admin" }
      }

      expect(response).to have_http_status(:forbidden)
      expect(target.reload.access_level).to eq("staff")
    end

    it "does not allow a senior admin to change another practice's staff" do
      user.staff_members.find_by!(practice: practice).update!(
        access_level: "senior_staff_admin"
      )
      foreign_staff = create(:staff_member, practice: create(:practice))
      sign_in user

      patch access_level_practice_staff_member_path(foreign_staff), params: {
        staff_member: { access_level: "staff_admin" }
      }

      expect(response).to have_http_status(:not_found)
      expect(foreign_staff.reload.access_level).to eq("staff")
    end
  end
end
