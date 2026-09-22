require "rails_helper"

RSpec.describe PatientIdentifier do
  describe "validations" do
    subject(:patient_identifier) { described_class.new }

    let(:patient) { create(:patient) }

    it "is not valid without an identifier type" do
      patient_identifier.patient = patient
      expect(patient_identifier).not_to be_valid
    end

    it "has an error on identifier_type" do
      patient_identifier.patient = patient
      patient_identifier.valid?
      expect(patient_identifier.errors[:identifier_type]).to be_present
    end

    it "is not valid without an identifier value" do
      patient_identifier.assign_attributes(patient: patient, identifier_type: "nhs_number")
      expect(patient_identifier).not_to be_valid
    end

    it "has an error on identifier_value" do
      patient_identifier.assign_attributes(patient: patient, identifier_type: "nhs_number")
      patient_identifier.valid?
      expect(patient_identifier.errors[:identifier_value]).to be_present
    end

    it "is not valid with a duplicate identifier for the same patient and type" do
      create(:patient_identifier, patient: patient, identifier_type: "nhs_number", identifier_value: "1234567890")
      patient_identifier.assign_attributes(
        patient: patient,
        identifier_type: "nhs_number",
        identifier_value: "1234567890"
      )
      expect(patient_identifier).not_to be_valid
    end

    it "has an error on identifier_value for a duplicate" do
      create(:patient_identifier, patient: patient, identifier_type: "nhs_number", identifier_value: "1234567890")
      patient_identifier.assign_attributes(
        patient: patient,
        identifier_type: "nhs_number",
        identifier_value: "1234567890"
      )
      patient_identifier.valid?
      expect(patient_identifier.errors[:identifier_value]).to be_present
    end

    it "is valid with the same value for a different identifier type" do
      create(:patient_identifier, patient: patient, identifier_type: "nhs_number", identifier_value: "1234567890")
      patient_identifier.assign_attributes(
        patient: patient,
        identifier_type: "passport",
        identifier_value: "1234567890"
      )
      expect(patient_identifier).to be_valid
    end
  end
end
