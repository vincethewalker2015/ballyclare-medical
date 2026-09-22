require "rails_helper"

RSpec.describe AppointmentStatusChange do
  describe "validations" do
    subject(:status_change) { described_class.new }

    let(:appointment) { create(:appointment) }
    let(:user) { create(:user) }

    it "is not valid without a to_status" do
      status_change.assign_attributes(appointment: appointment, changed_by: user)
      expect(status_change).not_to be_valid
    end

    it "has an error on to_status" do
      status_change.assign_attributes(appointment: appointment, changed_by: user)
      status_change.valid?
      expect(status_change.errors[:to_status]).to be_present
    end

    it "is not valid with an invalid to_status" do
      status_change.assign_attributes(appointment: appointment, changed_by: user, to_status: "invalid")
      expect(status_change).not_to be_valid
    end

    it "has an error on to_status for an invalid value" do
      status_change.assign_attributes(appointment: appointment, changed_by: user, to_status: "invalid")
      status_change.valid?
      expect(status_change.errors[:to_status]).to be_present
    end

    it "is not valid with an invalid from_status" do
      status_change.assign_attributes(
        appointment: appointment,
        changed_by: user,
        from_status: "invalid",
        to_status: "confirmed"
      )
      expect(status_change).not_to be_valid
    end

    it "has an error on from_status for an invalid value" do
      status_change.assign_attributes(
        appointment: appointment,
        changed_by: user,
        from_status: "invalid",
        to_status: "confirmed"
      )
      status_change.valid?
      expect(status_change.errors[:from_status]).to be_present
    end

    it "is valid with a nil from_status" do
      status_change.assign_attributes(
        appointment: appointment,
        changed_by: user,
        from_status: nil,
        to_status: "confirmed"
      )
      expect(status_change).to be_valid
    end

    it "is valid with valid status values" do
      status_change.assign_attributes(
        appointment: appointment,
        changed_by: user,
        from_status: "booked",
        to_status: "confirmed"
      )
      expect(status_change).to be_valid
    end
  end
end
