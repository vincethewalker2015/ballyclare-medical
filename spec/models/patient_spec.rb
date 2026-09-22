require "rails_helper"

RSpec.describe Patient do
  describe "validations" do
    subject(:patient) { described_class.new }

    let(:practice) { create(:practice) }

    it "is not valid without a practice" do
      expect(patient).not_to be_valid
    end

    it "has an error on practice" do
      patient.valid?
      expect(patient.errors[:practice]).to be_present
    end

    it "is not valid without a patient number" do
      patient.practice = practice
      expect(patient).not_to be_valid
    end

    it "has an error on patient_number" do
      patient.practice = practice
      patient.valid?
      expect(patient.errors[:patient_number]).to be_present
    end

    it "is not valid without a first name" do
      patient.assign_attributes(practice: practice, patient_number: "P000001", last_name: "Doe", date_of_birth: Date.new(1990, 1, 1))
      expect(patient).not_to be_valid
    end

    it "has an error on first_name" do
      patient.assign_attributes(practice: practice, patient_number: "P000001", last_name: "Doe", date_of_birth: Date.new(1990, 1, 1))
      patient.valid?
      expect(patient.errors[:first_name]).to be_present
    end

    it "is not valid without a last name" do
      patient.assign_attributes(practice: practice, patient_number: "P000001", first_name: "Jane", date_of_birth: Date.new(1990, 1, 1))
      expect(patient).not_to be_valid
    end

    it "has an error on last_name" do
      patient.assign_attributes(practice: practice, patient_number: "P000001", first_name: "Jane", date_of_birth: Date.new(1990, 1, 1))
      patient.valid?
      expect(patient.errors[:last_name]).to be_present
    end

    it "is not valid without a date of birth" do
      patient.assign_attributes(practice: practice, patient_number: "P000001", first_name: "Jane", last_name: "Doe")
      expect(patient).not_to be_valid
    end

    it "has an error on date_of_birth" do
      patient.assign_attributes(practice: practice, patient_number: "P000001", first_name: "Jane", last_name: "Doe")
      patient.valid?
      expect(patient.errors[:date_of_birth]).to be_present
    end

    it "is not valid with a duplicate patient number in the same practice" do
      create(:patient, practice: practice, patient_number: "P000001")
      patient.assign_attributes(
        practice: practice,
        patient_number: "P000001",
        first_name: "John",
        last_name: "Smith",
        date_of_birth: Date.new(1985, 5, 5)
      )
      expect(patient).not_to be_valid
    end

    it "has an error on patient_number for a duplicate in the same practice" do
      create(:patient, practice: practice, patient_number: "P000001")
      patient.assign_attributes(
        practice: practice,
        patient_number: "P000001",
        first_name: "John",
        last_name: "Smith",
        date_of_birth: Date.new(1985, 5, 5)
      )
      patient.valid?
      expect(patient.errors[:patient_number]).to be_present
    end

    it "is valid with the same patient number in a different practice" do
      other_practice = create(:practice)
      create(:patient, practice: practice, patient_number: "P000001")
      patient.assign_attributes(
        practice: other_practice,
        patient_number: "P000001",
        first_name: "John",
        last_name: "Smith",
        date_of_birth: Date.new(1985, 5, 5)
      )
      expect(patient).to be_valid
    end
  end
end
