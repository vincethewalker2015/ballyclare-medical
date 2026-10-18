require "rails_helper"

RSpec.describe Staff::ProvisionUserAccount do
  describe "#call" do
    it "creates a user with a generated password for a new email" do
      expect {
        described_class.new(email: "new.clinician@example.com").call
      }.to change(User, :count).by(1)

      user = User.find_by!(email: "new.clinician@example.com")
      expect(user.encrypted_password).to be_present
      expect(user.valid_password?("password123")).to be(false)
    end

    it "reuses an existing account without changing its password" do
      existing_user = create(:user, email: "existing@example.com")
      encrypted_password = existing_user.encrypted_password

      expect {
        result = described_class.new(email: "EXISTING@EXAMPLE.COM").call
        expect(result).to eq(existing_user)
      }.not_to change(User, :count)

      expect(existing_user.reload.encrypted_password).to eq(encrypted_password)
    end

    it "rejects invalid email addresses without creating accounts" do
      expect {
        described_class.new(email: "invalid-email").call
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(User.find_by(email: "invalid-email")).to be_nil
    end
  end
end
