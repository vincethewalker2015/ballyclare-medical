require "rails_helper"

RSpec.describe UserRole do
  describe "validations" do
    subject(:user_role) { described_class.new }

    let(:user) { create(:user) }
    let(:role) { create(:role) }

    it "is not valid without a user" do
      expect(user_role).not_to be_valid
    end

    it "has an error on user" do
      user_role.valid?
      expect(user_role.errors[:user]).to be_present
    end

    it "is not valid without a role" do
      user_role.user = user
      expect(user_role).not_to be_valid
    end

    it "has an error on role" do
      user_role.user = user
      user_role.valid?
      expect(user_role.errors[:role]).to be_present
    end

    it "is not valid with a duplicate role for the same user" do
      create(:user_role, user: user, role: role)
      user_role.user = user
      user_role.role = role
      expect(user_role).not_to be_valid
    end

    it "has an error on role_id for a duplicate assignment" do
      create(:user_role, user: user, role: role)
      user_role.user = user
      user_role.role = role
      user_role.valid?
      expect(user_role.errors[:role_id]).to be_present
    end

    it "is valid with a user and role" do
      user_role.user = user
      user_role.role = role
      expect(user_role).to be_valid
    end
  end
end
