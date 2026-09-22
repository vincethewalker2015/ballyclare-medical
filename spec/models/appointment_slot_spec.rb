require "rails_helper"

RSpec.describe AppointmentSlot do
  describe "validations" do
    subject(:appointment_slot) { described_class.new }

    let(:practice) { create(:practice) }
    let(:clinician) { create(:staff_member, practice: practice) }
    let(:availability_block) { create(:availability_block, practice: practice, clinician: clinician) }

    it "is not valid without a starts_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        ends_at: 1.hour.from_now
      )
      expect(appointment_slot).not_to be_valid
    end

    it "has an error on starts_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        ends_at: 1.hour.from_now
      )
      appointment_slot.valid?
      expect(appointment_slot.errors[:starts_at]).to be_present
    end

    it "is not valid without an ends_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        starts_at: Time.current
      )
      expect(appointment_slot).not_to be_valid
    end

    it "has an error on ends_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        starts_at: Time.current
      )
      appointment_slot.valid?
      expect(appointment_slot.errors[:ends_at]).to be_present
    end

    it "is not valid when ends_at is before starts_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        starts_at: 2.hours.from_now,
        ends_at: 1.hour.from_now
      )
      expect(appointment_slot).not_to be_valid
    end

    it "has an error on ends_at when it is before starts_at" do
      appointment_slot.assign_attributes(
        practice: practice,
        clinician: clinician,
        availability_block: availability_block,
        starts_at: 2.hours.from_now,
        ends_at: 1.hour.from_now
      )
      appointment_slot.valid?
      expect(appointment_slot.errors[:ends_at]).to include("must be after starts_at")
    end
  end

  describe ".upcoming" do
    it "includes slots starting in the future" do
      future_slot = create(:appointment_slot, starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
      expect(described_class.upcoming).to include(future_slot)
    end

    it "excludes slots starting in the past" do
      past_slot = create(:appointment_slot, starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      expect(described_class.upcoming).not_to include(past_slot)
    end
  end
end
