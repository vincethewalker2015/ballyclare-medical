require "rails_helper"

RSpec.describe StaffMember do
  describe "validations" do
    subject(:staff_member) { described_class.new }

    let(:practice) { create(:practice) }
    let(:user) { create(:user) }

    it "is not valid without a staff type" do
      staff_member.practice = practice
      staff_member.user = user
      expect(staff_member).not_to be_valid
    end

    it "has an error on staff_type" do
      staff_member.practice = practice
      staff_member.user = user
      staff_member.valid?
      expect(staff_member.errors[:staff_type]).to be_present
    end

    it "is not valid with an invalid staff type" do
      staff_member.assign_attributes(practice: practice, user: user, staff_type: "receptionist")
      expect(staff_member).not_to be_valid
    end

    it "has an error on staff_type for an invalid value" do
      staff_member.assign_attributes(practice: practice, user: user, staff_type: "receptionist")
      staff_member.valid?
      expect(staff_member.errors[:staff_type]).to be_present
    end

    it "is not valid with a zero default appointment duration" do
      staff_member.assign_attributes(
        practice: practice,
        user: user,
        staff_type: "doctor",
        default_appointment_duration: 0
      )
      expect(staff_member).not_to be_valid
    end

    it "has an error on default_appointment_duration for zero" do
      staff_member.assign_attributes(
        practice: practice,
        user: user,
        staff_type: "doctor",
        default_appointment_duration: 0
      )
      staff_member.valid?
      expect(staff_member.errors[:default_appointment_duration]).to be_present
    end

    it "is valid with required attributes" do
      staff_member.assign_attributes(
        practice: practice,
        user: user,
        staff_type: "doctor",
        default_appointment_duration: 20
      )
      expect(staff_member).to be_valid
    end

    it "is valid with administrator as a staff type" do
      staff_member.assign_attributes(
        practice: practice,
        user: user,
        staff_type: "administrator",
        default_appointment_duration: 20
      )
      expect(staff_member).to be_valid
    end

    it "persists an administrator staff member" do
      staff_member = create(
        :staff_member,
        practice: practice,
        user: user,
        staff_type: "administrator"
      )
      expect(staff_member).to be_persisted
    end
  end
  describe "practice-specific access levels" do
    it "defaults new staff members to ordinary staff access" do
      staff_member = create(:staff_member)

      expect(staff_member.reload.access_level).to eq("staff")
    end

    it "persists a senior administrator privilege only on that practice membership" do
      user = create(:user)
      primary_practice = create(:practice)
      other_practice = create(:practice)

      senior_membership = create(
        :staff_member,
        user: user,
        practice: primary_practice,
        access_level: "senior_staff_admin"
      )
      other_membership = create(
        :staff_member,
        user: user,
        practice: other_practice
      )

      expect(senior_membership.reload.access_level).to eq("senior_staff_admin")
      expect(other_membership.reload.access_level).to eq("staff")
    end

    it "rejects unrecognised access levels" do
      staff_member = build(:staff_member, access_level: "superuser")

      expect(staff_member).not_to be_valid
      expect(staff_member.errors[:access_level]).to be_present
    end
  end
end
