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

    it "shows staff type and access level as separate directory information" do
      admin = user.staff_members.find_by!(practice: practice)
      admin.update!(access_level: "senior_staff_admin")
      create(:staff_member, practice: practice, first_name: "Helen",
        last_name: "Nurse", staff_type: "nurse", access_level: "staff")
      sign_in user

      get practice_staff_members_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Staff type")
      expect(response.body).to include("Access level")
      expect(response.body).to include("Senior Staff Admin")
      expect(response.body).to include("Nurse")
    end

    it "offers access-level editing only to senior staff admins" do
      target = create(:staff_member, practice: practice, first_name: "Helen",
        last_name: "Nurse", staff_type: "nurse", access_level: "staff")
      admin = user.staff_members.find_by!(practice: practice)
      sign_in user

      get practice_staff_members_path
      expect(response.body).not_to include("Change access level")

      admin.update!(access_level: "senior_staff_admin")
      get practice_staff_members_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Edit access")
      expect(response.body).to include("Change access level")
      expect(response.body).to include("<details")
      expect(response.body).to include("Cancel")
      expect(response.body).to include(access_level_practice_staff_member_path(target))
    end

    it "identifies the signed-in staff member in the practice header" do
      membership = user.staff_members.find_by!(practice: practice)
      membership.update!(first_name: "Alex", last_name: "Morgan",
        access_level: "senior_staff_admin")
      sign_in user

      get practice_staff_members_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('aria-label="Signed-in account"')
      expect(response.body).to include("Alex Morgan")
      expect(response.body).to include(user.email)
      expect(response.body).to include("Senior Staff Admin")
    end

    it "shows a Staff navigation link and a compact signed-in identity" do
      sign_in user

      get practice_staff_members_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('href="' + practice_staff_members_path + '"')
      expect(response.body).to include('aria-current="page"')
      expect(response.body).to include('aria-label="Signed-in account"')
      expect(response.body).to include(user.email)
      expect(response.body).not_to include("Staff workspace")
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

    it "allows a senior staff admin to assign Staff Clinician access to a nurse" do
      senior = user.staff_members.find_by!(practice: practice)
      senior.update!(access_level: "senior_staff_admin")
      clinician = create(:staff_member, practice: practice, staff_type: "nurse")
      sign_in user

      patch access_level_practice_staff_member_path(clinician), params: {
        staff_member: { access_level: "staff_clinician" }
      }

      expect(response).to redirect_to(practice_staff_members_path)
      expect(clinician.reload.access_level).to eq("staff_clinician")
    end

    it "rejects Staff Clinician access for an administrator" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "senior_staff_admin")
      administrator = create(:staff_member, practice: practice, staff_type: "administrator")
      sign_in user

      patch access_level_practice_staff_member_path(administrator), params: {
        staff_member: { access_level: "staff_clinician" }
      }

      expect(response).to redirect_to(practice_staff_members_path)
      expect(administrator.reload.access_level).to eq("staff")
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

    it "rejects an unrecognised access level without changing the staff member" do
      user.staff_members.find_by!(practice: practice).update!(
        access_level: "senior_staff_admin"
      )
      sign_in user

      patch access_level_practice_staff_member_path(target), params: {
        staff_member: { access_level: "superuser" }
      }

      expect(response).to redirect_to(practice_staff_members_path)
      expect(target.reload.access_level).to eq("staff")
    end

    it "prevents a senior staff admin from demoting themselves" do
      senior = user.staff_members.find_by!(practice: practice)
      senior.update!(access_level: "senior_staff_admin")
      sign_in user

      patch access_level_practice_staff_member_path(senior), params: {
        staff_member: { access_level: "staff" }
      }

      expect(response).to have_http_status(:forbidden)
      expect(senior.reload.access_level).to eq("senior_staff_admin")
    end

    it "preserves the last senior staff admin even when another senior tries to demote them" do
      senior = user.staff_members.find_by!(practice: practice)
      senior.update!(access_level: "senior_staff_admin")
      second_senior = create(
        :staff_member, practice: practice, access_level: "senior_staff_admin"
      )
      sign_in user

      patch access_level_practice_staff_member_path(second_senior), params: {
        staff_member: { access_level: "staff" }
      }

      expect(response).to redirect_to(practice_staff_members_path)
      expect(second_senior.reload.access_level).to eq("staff")
      expect(senior.reload.access_level).to eq("senior_staff_admin")
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
  describe "staff creation" do
    let(:colleague) { create(:user) }

    it "lets a staff admin open the new staff form" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      get new_practice_staff_member_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("New staff member")
    end

    it "forbids ordinary staff from opening the creation form" do
      sign_in user

      get new_practice_staff_member_path

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects user-ID-only creation without linking an existing account" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      expect {
        post practice_staff_members_path, params: {
          staff_member: {
            user_id: colleague.id,
            first_name: "Alex",
            last_name: "Smith",
            staff_type: "nurse"
          }
        }
      }.not_to change(StaffMember, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(practice.staff_members.find_by(user: colleague)).to be_nil
    end

    it "ignores an injected user ID when creating staff by email" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      post practice_staff_members_path, params: {
        staff_member: {
          user_id: colleague.id,
          email: "safe.new.staff@example.com",
          first_name: "Alex",
          last_name: "Smith",
          staff_type: "nurse"
        }
      }

      expect(response).to redirect_to(practice_staff_members_path)
      expect(practice.staff_members.find_by(user: colleague)).to be_nil
      expect(practice.staff_members.find_by!(
        user: User.find_by!(email: "safe.new.staff@example.com")
      ).access_level).to eq("staff")
    end

    it "lets a staff admin add an existing user with ordinary staff access" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      expect {
        post practice_staff_members_path, params: {
          staff_member: {
            email: colleague.email,
            first_name: "Alex",
            last_name: "Smith",
            staff_type: "nurse",
            access_level: "senior_staff_admin",
            practice_id: create(:practice).id
          }
        }
      }.to change(practice.staff_members, :count).by(1)

      membership = practice.staff_members.find_by!(user: colleague)
      expect(membership).to have_attributes(
        first_name: "Alex",
        last_name: "Smith",
        staff_type: "nurse",
        access_level: "staff"
      )
      expect(response).to redirect_to(practice_staff_members_path)
    end

    it "lets a senior staff admin create a membership with staff access" do
      user.staff_members.find_by!(practice: practice).update!(
        access_level: "senior_staff_admin"
      )
      sign_in user

      post practice_staff_members_path, params: {
        staff_member: {
          email: colleague.email,
          first_name: "Alex",
          last_name: "Smith",
          staff_type: "doctor",
          access_level: "senior_staff_admin"
        }
      }

      expect(response).to redirect_to(practice_staff_members_path)
      expect(practice.staff_members.find_by!(user: colleague).access_level).to eq("staff")
    end

    it "rejects a duplicate membership without creating a second record" do
      create(:staff_member, practice: practice, user: colleague)
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      expect {
        post practice_staff_members_path, params: {
          staff_member: {
            email: colleague.email,
            first_name: "Duplicate",
            last_name: "Account",
            staff_type: "nurse"
          }
        }
      }.not_to change(StaffMember, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "sends password-setting instructions after creating a new staff account" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user
      ActionMailer::Base.deliveries.clear

      post practice_staff_members_path, params: {
        staff_member: {
          email: "welcome.nurse@example.com",
          first_name: "Alex",
          last_name: "Smith",
          staff_type: "nurse"
        }
      }

      expect(response).to redirect_to(practice_staff_members_path)
      expect(ActionMailer::Base.deliveries.map(&:to).flatten)
        .to include("welcome.nurse@example.com")
      expect(User.find_by!(email: "welcome.nurse@example.com").reset_password_sent_at)
        .to be_present
    end

    it "does not send password-setting instructions if staff creation fails" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user
      ActionMailer::Base.deliveries.clear

      post practice_staff_members_path, params: {
        staff_member: {
          email: "not-invited@example.com",
          first_name: "Alex",
          last_name: "Smith",
          staff_type: "invalid_type"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(User.find_by(email: "not-invited@example.com")).to be_nil
    end

    it "rolls back a new user account when staff membership validation fails" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      expect {
        post practice_staff_members_path, params: {
          staff_member: {
            email: "unassigned@example.com",
            first_name: "Alex",
            last_name: "Smith",
            staff_type: "invalid_type"
          }
        }
      }.not_to change { [ User.count, StaffMember.count ] }

      expect(response).to have_http_status(:unprocessable_content)
      expect(User.find_by(email: "unassigned@example.com")).to be_nil
    end

    it "handles a concurrent duplicate insert as a validation error" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      allow_any_instance_of(StaffMember).to receive(:save!)
        .and_raise(ActiveRecord::RecordNotUnique)

      post practice_staff_members_path, params: {
        staff_member: {
          email: colleague.email,
          first_name: "Alex",
          last_name: "Smith",
          staff_type: "nurse"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("already")
    end

    it "does not ask for a default appointment duration" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      get new_practice_staff_member_path

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Default appointment duration")
      expect(response.body).not_to include('name="staff_member[default_appointment_duration]"')
    end

    it "shows an email field instead of asking for a user account ID" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      get new_practice_staff_member_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('name="staff_member[email]"')
      expect(response.body).not_to include('name="staff_member[user_id]"')
    end

    it "creates an ordinary staff membership using a new email address" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      expect {
        post practice_staff_members_path, params: {
          staff_member: {
            email: "new.nurse@example.com",
            first_name: "Alex",
            last_name: "Smith",
            staff_type: "nurse",
            access_level: "senior_staff_admin"
          }
        }
      }.to change(User, :count).by(1)
        .and change(practice.staff_members, :count).by(1)

      membership = practice.staff_members.find_by!(
        user: User.find_by!(email: "new.nurse@example.com")
      )
      expect(membership.access_level).to eq("staff")
      expect(response).to redirect_to(practice_staff_members_path)
    end

    it "reuses an existing account by email without changing its password" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      password_digest = colleague.encrypted_password
      sign_in user

      expect {
        post practice_staff_members_path, params: {
          staff_member: {
            email: colleague.email,
            first_name: "Alex",
            last_name: "Smith",
            staff_type: "doctor"
          }
        }
      }.not_to change(User, :count)

      expect(response).to redirect_to(practice_staff_members_path)
      expect(practice.staff_members.find_by!(user: colleague).access_level).to eq("staff")
      expect(colleague.reload.encrypted_password).to eq(password_digest)
    end

    it "does not send password-setting instructions for an existing user" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      existing_digest = colleague.encrypted_password
      sign_in user
      ActionMailer::Base.deliveries.clear

      post practice_staff_members_path, params: {
        staff_member: {
          email: colleague.email,
          first_name: "Alex",
          last_name: "Smith",
          staff_type: "doctor"
        }
      }

      expect(response).to redirect_to(practice_staff_members_path)
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(colleague.reload.encrypted_password).to eq(existing_digest)
      expect(colleague.reset_password_sent_at).to be_nil
    end

    it "does not create an account or membership for an invalid email address" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      expect {
        post practice_staff_members_path, params: {
          staff_member: {
            email: "not-an-email",
            first_name: "Alex",
            last_name: "Smith",
            staff_type: "nurse"
          }
        }
      }.not_to change { [ User.count, StaffMember.count ] }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "forbids ordinary staff from creating a staff membership" do
      sign_in user

      expect {
        post practice_staff_members_path, params: {
          staff_member: {
            email: colleague.email,
            staff_type: "doctor",
            access_level: "senior_staff_admin"
          }
        }
      }.not_to change(StaffMember, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end
  describe "staff details editing" do
    let(:target) do
      create(:staff_member, practice: practice, first_name: "Helen",
        last_name: "Nurse", staff_type: "nurse")
    end

    it "lets a staff admin open the edit form" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      get edit_practice_staff_member_path(target)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Edit staff member")
      expect(response.body).to include("Registration number")
      expect(response.body).not_to include('name="staff_member[access_level]"')
    end

    it "updates staff details without changing access or account ownership" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user
      original_user_id = target.user_id

      patch practice_staff_member_path(target), params: {
        staff_member: { first_name: "Helena", last_name: "Smith",
          registration_number: "NMC-123", staff_type: "nurse",
          access_level: "senior_staff_admin", user_id: user.id,
          practice_id: create(:practice).id, active: false }
      }

      expect(response).to redirect_to(practice_staff_members_path)
      expect(target.reload).to have_attributes(first_name: "Helena",
        last_name: "Smith", registration_number: "NMC-123",
        access_level: "staff", user_id: original_user_id, active: true,
        practice_id: practice.id)
    end

    it "lets a senior staff admin edit staff details" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "senior_staff_admin")
      sign_in user

      patch practice_staff_member_path(target), params: {
        staff_member: { first_name: "Helena" }
      }

      expect(response).to redirect_to(practice_staff_members_path)
      expect(target.reload.first_name).to eq("Helena")
    end

    it "forbids clinicians from opening or submitting edits" do
      user.staff_members.find_by!(practice: practice).update!(
        staff_type: "doctor", access_level: "staff_clinician"
      )
      sign_in user

      get edit_practice_staff_member_path(target)
      expect(response).to have_http_status(:forbidden)

      patch practice_staff_member_path(target), params: {
        staff_member: { first_name: "Changed" }
      }
      expect(response).to have_http_status(:forbidden)
      expect(target.reload.first_name).to eq("Helen")
    end

    it "does not allow editing a staff member from another practice" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      foreign_staff = create(:staff_member, practice: create(:practice))
      sign_in user

      get edit_practice_staff_member_path(foreign_staff)

      expect(response).to have_http_status(:not_found)
    end

    it "does not allow updating a staff member from another practice" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      foreign_staff = create(:staff_member, practice: create(:practice))
      sign_in user

      patch practice_staff_member_path(foreign_staff), params: {
        staff_member: { first_name: "Changed" }
      }

      expect(response).to have_http_status(:not_found)
      expect(foreign_staff.reload.first_name).not_to eq("Changed")
    end

    it "renders validation errors without saving invalid staff types" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      sign_in user

      patch practice_staff_member_path(target), params: {
        staff_member: { staff_type: "invalid_type" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Edit staff member")
      expect(target.reload.staff_type).to eq("nurse")
    end

    it "rejects removing a clinician type while clinician access is assigned" do
      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      target.update!(access_level: "staff_clinician")
      sign_in user

      patch practice_staff_member_path(target), params: {
        staff_member: { staff_type: "administrator" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(target.reload.staff_type).to eq("nurse")
    end

    it "shows edit links only to administrators" do
      target
      sign_in user
      get practice_staff_members_path
      expect(response.body).not_to include("Edit details")

      user.staff_members.find_by!(practice: practice).update!(access_level: "staff_admin")
      get practice_staff_members_path
      expect(response.body).to include(edit_practice_staff_member_path(target))
    end
  end

end
