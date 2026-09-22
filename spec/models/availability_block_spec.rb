require "rails_helper"

RSpec.describe AvailabilityBlock do
  describe "validations" do
    subject(:availability_block) { described_class.new }

    let(:practice) { create(:practice) }
    let(:clinician) { create(:staff_member, practice: practice) }

    it "is not valid without a starts_at" do
      availability_block.assign_attributes(practice: practice, clinician: clinician, ends_at: 1.hour.from_now)
      expect(availability_block).not_to be_valid
    end

    it "has an error on starts_at" do
      availability_block.assign_attributes(practice: practice, clinician: clinician, ends_at: 1.hour.from_now)
      availability_block.valid?
      expect(availability_block.errors[:starts_at]).to be_present
    end

    it "is not valid without an ends_at" do
      availability_block.assign_attributes(practice: practice, clinician: clinician, starts_at: Time.current)
      expect(availability_block).not_to be_valid
    end

    it "has an error on ends_at" do
      availability_block.assign_attributes(practice: practice, clinician: clinician, starts_at: Time.current)
      availability_block.valid?
      expect(availability_block.errors[:ends_at]).to be_present
    end

    it "is not valid when ends_at is before starts_at" do
      availability_block.assign_attributes(
        practice: practice,
        clinician: clinician,
        starts_at: 2.hours.from_now,
        ends_at: 1.hour.from_now
      )
      expect(availability_block).not_to be_valid
    end

    it "has an error on ends_at when it is before starts_at" do
      availability_block.assign_attributes(
        practice: practice,
        clinician: clinician,
        starts_at: 2.hours.from_now,
        ends_at: 1.hour.from_now
      )
      availability_block.valid?
      expect(availability_block.errors[:ends_at]).to include("must be after starts_at")
    end

    it "is not valid with a zero slot duration" do
      availability_block.assign_attributes(
        practice: practice,
        clinician: clinician,
        starts_at: 1.hour.from_now,
        ends_at: 3.hours.from_now,
        slot_duration_minutes: 0
      )
      expect(availability_block).not_to be_valid
    end

    it "has an error on slot_duration_minutes for zero" do
      availability_block.assign_attributes(
        practice: practice,
        clinician: clinician,
        starts_at: 1.hour.from_now,
        ends_at: 3.hours.from_now,
        slot_duration_minutes: 0
      )
      availability_block.valid?
      expect(availability_block.errors[:slot_duration_minutes]).to be_present
    end

    it "is valid with required attributes" do
      availability_block.assign_attributes(
        practice: practice,
        clinician: clinician,
        starts_at: 1.hour.from_now,
        ends_at: 3.hours.from_now,
        slot_duration_minutes: 20
      )
      expect(availability_block).to be_valid
    end
  end
end
