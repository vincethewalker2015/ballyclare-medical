require "rails_helper"

RSpec.describe ClinicalNote do
  describe "validations" do
    subject(:clinical_note) { described_class.new }

    let(:practice) { create(:practice) }
    let(:patient) { create(:patient, practice: practice) }
    let(:clinician) { create(:staff_member, practice: practice) }
    let(:encounter) { create(:encounter, practice: practice, patient: patient, clinician: clinician) }

    it "is not valid without a note type" do
      clinical_note.assign_attributes(patient: patient, encounter: encounter, author: clinician, body: "Note body")
      expect(clinical_note).not_to be_valid
    end

    it "has an error on note_type" do
      clinical_note.assign_attributes(patient: patient, encounter: encounter, author: clinician, body: "Note body")
      clinical_note.valid?
      expect(clinical_note.errors[:note_type]).to be_present
    end

    it "is not valid without a body" do
      clinical_note.assign_attributes(patient: patient, encounter: encounter, author: clinician, note_type: "general")
      expect(clinical_note).not_to be_valid
    end

    it "has an error on body" do
      clinical_note.assign_attributes(patient: patient, encounter: encounter, author: clinician, note_type: "general")
      clinical_note.valid?
      expect(clinical_note.errors[:body]).to be_present
    end

    it "is valid with required attributes" do
      clinical_note.assign_attributes(
        patient: patient,
        encounter: encounter,
        author: clinician,
        note_type: "general",
        body: "Patient presented with mild symptoms."
      )
      expect(clinical_note).to be_valid
    end
  end
end
