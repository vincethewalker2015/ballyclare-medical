require "rails_helper"

RSpec.describe Encounter do
  describe "validations" do
    subject(:encounter) { described_class.new }

    let(:practice) { create(:practice) }
    let(:patient) { create(:patient, practice: practice) }
    let(:clinician) { create(:staff_member, practice: practice) }

    it "is not valid without an encounter type" do
      encounter.assign_attributes(practice: practice, patient: patient, clinician: clinician, started_at: Time.current)
      expect(encounter).not_to be_valid
    end

    it "has an error on encounter_type" do
      encounter.assign_attributes(practice: practice, patient: patient, clinician: clinician, started_at: Time.current)
      encounter.valid?
      expect(encounter.errors[:encounter_type]).to be_present
    end

    it "is not valid without a started_at" do
      encounter.assign_attributes(
        practice: practice,
        patient: patient,
        clinician: clinician,
        encounter_type: "consultation"
      )
      expect(encounter).not_to be_valid
    end

    it "has an error on started_at" do
      encounter.assign_attributes(
        practice: practice,
        patient: patient,
        clinician: clinician,
        encounter_type: "consultation"
      )
      encounter.valid?
      expect(encounter.errors[:started_at]).to be_present
    end

    it "is not valid when ended_at is before started_at" do
      encounter.assign_attributes(
        practice: practice,
        patient: patient,
        clinician: clinician,
        encounter_type: "consultation",
        started_at: 2.hours.from_now,
        ended_at: 1.hour.from_now
      )
      expect(encounter).not_to be_valid
    end

    it "has an error on ended_at when it is before started_at" do
      encounter.assign_attributes(
        practice: practice,
        patient: patient,
        clinician: clinician,
        encounter_type: "consultation",
        started_at: 2.hours.from_now,
        ended_at: 1.hour.from_now
      )
      encounter.valid?
      expect(encounter.errors[:ended_at]).to include("must not be before started_at")
    end

    it "is valid with required attributes" do
      encounter.assign_attributes(
        practice: practice,
        patient: patient,
        clinician: clinician,
        encounter_type: "consultation",
        started_at: Time.current
      )
      expect(encounter).to be_valid
    end
  end
end
