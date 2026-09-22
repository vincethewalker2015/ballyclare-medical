require "rails_helper"

RSpec.describe AppointmentHold do
  describe "validations" do
    subject(:appointment_hold) { described_class.new }

    let(:appointment_slot) { create(:appointment_slot) }
    let(:patient) { create(:patient, practice: appointment_slot.practice) }

    it "is not valid without an expires_at" do
      appointment_hold.assign_attributes(appointment_slot: appointment_slot, patient: patient)
      expect(appointment_hold).not_to be_valid
    end

    it "has an error on expires_at" do
      appointment_hold.assign_attributes(appointment_slot: appointment_slot, patient: patient)
      appointment_hold.valid?
      expect(appointment_hold.errors[:expires_at]).to be_present
    end

    it "is valid with required attributes" do
      appointment_hold.assign_attributes(
        appointment_slot: appointment_slot,
        patient: patient,
        expires_at: 15.minutes.from_now
      )
      expect(appointment_hold).to be_valid
    end
  end

  describe "#expired?" do
    subject(:appointment_hold) { build(:appointment_hold, expires_at: expires_at) }

    let(:expires_at) { 1.hour.from_now }

    it "returns false when the hold has not expired" do
      expect(appointment_hold.expired?).to be(false)
    end

    context "when the hold has expired" do
      let(:expires_at) { 1.hour.ago }

      it "returns true" do
        expect(appointment_hold.expired?).to be(true)
      end
    end
  end

  describe ".active" do
    it "includes holds that have not expired" do
      active_hold = create(:appointment_hold, expires_at: 1.hour.from_now)
      expect(described_class.active).to include(active_hold)
    end

    it "excludes holds that have expired" do
      expired_hold = create(:appointment_hold, expires_at: 1.hour.ago)
      expect(described_class.active).not_to include(expired_hold)
    end
  end

  describe ".expired" do
    it "includes holds that have expired" do
      expired_hold = create(:appointment_hold, expires_at: 1.hour.ago)
      expect(described_class.expired).to include(expired_hold)
    end

    it "excludes holds that have not expired" do
      active_hold = create(:appointment_hold, expires_at: 1.hour.from_now)
      expect(described_class.expired).not_to include(active_hold)
    end
  end
end
