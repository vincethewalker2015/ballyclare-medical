require "rails_helper"

RSpec.describe Role do
  describe "validations" do
    subject(:role) { described_class.new }

    it "is not valid without a name" do
      expect(role).not_to be_valid
    end

    it "has an error on name" do
      role.valid?
      expect(role.errors[:name]).to be_present
    end

    it "is not valid with a duplicate name" do
      create(:role, name: "admin")
      role.name = "admin"
      expect(role).not_to be_valid
    end

    it "has an error on name for a duplicate" do
      create(:role, name: "admin")
      role.name = "admin"
      role.valid?
      expect(role.errors[:name]).to be_present
    end

    it "is valid with a unique name" do
      role.name = "receptionist"
      expect(role).to be_valid
    end
  end
end
