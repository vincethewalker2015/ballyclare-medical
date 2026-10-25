require "rails_helper"

RSpec.describe PatientAccount do
  describe "validations" do
    it "requires an email" do
      expect(build(:patient_account, email: "")).not_to be_valid
    end

    it "requires a password" do
      expect(build(:patient_account, password: nil)).not_to be_valid
    end

    it "rejects duplicate email addresses" do
      create(:patient_account, email: "duplicate@example.com")

      expect(build(:patient_account, email: "duplicate@example.com")).not_to be_valid
    end

    it "accepts valid registration details" do
      expect(build(:patient_account)).to be_valid
    end
  end

  describe "confirmation" do
    it "requires email confirmation" do
      account = create(:patient_account)

      expect(account).not_to be_confirmed
      expect(account).not_to be_active_for_authentication
    end

    it "allows authentication after confirmation" do
      account = create(:patient_account)
      account.confirm

      expect(account).to be_confirmed
      expect(account).to be_active_for_authentication
    end

    it "does not change staff user authentication" do
      user = create(:user)

      expect(user).to be_active_for_authentication
      expect(User.devise_modules).not_to include(:confirmable)
    end
  end
end
