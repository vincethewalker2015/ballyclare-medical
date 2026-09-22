require "rails_helper"

RSpec.describe AuditEvent do
  describe "validations" do
    subject(:audit_event) { described_class.new }

    let(:practice) { create(:practice) }
    let(:patient) { create(:patient, practice: practice) }

    it "is not valid without an action" do
      audit_event.assign_attributes(practice: practice, auditable: patient)
      expect(audit_event).not_to be_valid
    end

    it "has an error on action" do
      audit_event.assign_attributes(practice: practice, auditable: patient)
      audit_event.valid?
      expect(audit_event.errors[:action]).to be_present
    end

    it "is valid with required attributes" do
      audit_event.assign_attributes(practice: practice, auditable: patient, action: "patient.updated")
      expect(audit_event).to be_valid
    end
  end
end
