require "rails_helper"

RSpec.describe User do
  describe "validations" do
    subject(:user) { described_class.new }

    it "is not valid without an email" do
      expect(user).not_to be_valid
    end

    it "has an error on email" do
      user.valid?
      expect(user.errors[:email]).to be_present
    end

    it "is not valid without a password" do
      user.email = "patient@example.com"
      expect(user).not_to be_valid
    end

    it "has an error on password" do
      user.email = "patient@example.com"
      user.valid?
      expect(user.errors[:password]).to be_present
    end

    it "is not valid with a duplicate email" do
      create(:user, email: "duplicate@example.com")
      user.email = "duplicate@example.com"
      user.password = "password123"
      expect(user).not_to be_valid
    end

    it "has an error on email for a duplicate" do
      create(:user, email: "duplicate@example.com")
      user.email = "duplicate@example.com"
      user.password = "password123"
      user.valid?
      expect(user.errors[:email]).to be_present
    end

    it "is valid with email and password" do
      user.email = "newuser@example.com"
      user.password = "password123"
      expect(user).to be_valid
    end
  end
end
