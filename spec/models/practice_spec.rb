require "rails_helper"

RSpec.describe Practice do
  describe "validations" do
    subject(:practice) { described_class.new }

    it "is not valid without a name" do
      expect(practice).not_to be_valid
    end

    it "has an error on name" do
      practice.valid?
      expect(practice.errors[:name]).to be_present
    end

    it "is not valid without a timezone" do
      expect(practice).not_to be_valid
    end

    it "has an error on timezone" do
      practice.valid?
      expect(practice.errors[:timezone]).to be_present
    end

    it "is not valid without a currency" do
      expect(practice).not_to be_valid
    end

    it "has an error on currency" do
      practice.valid?
      expect(practice.errors[:currency]).to be_present
    end

    it "is valid with required attributes" do
      practice.assign_attributes(
        name: "Ballyclare Medical Centre",
        timezone: "Europe/London",
        currency: "GBP",
        country_code: "GB"
      )
      expect(practice).to be_valid
    end
  end
end
