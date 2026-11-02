require "rails_helper"

RSpec.describe "Clinical record practice ownership", type: :model do
  let(:group) { create(:medical_group) }
  let(:practice_a) { create(:practice, medical_group: group) }
  let(:practice_b) { create(:practice, medical_group: group) }
  let(:other_group_practice) { create(:practice) }

  it "accepts an encounter with a patient and clinician from its own practice" do
    encounter = build(:encounter, practice: practice_a)

    expect(encounter).to be_valid
  end

  it "rejects an encounter linked to a patient from a sibling practice" do
    encounter = build(:encounter, practice: practice_a, patient: create(:patient, practice: practice_b))

    expect(encounter).not_to be_valid
  end

  it "rejects an encounter linked to a clinician from another medical group" do
    encounter = build(:encounter, practice: practice_a, clinician: create(:staff_member, practice: other_group_practice))

    expect(encounter).not_to be_valid
  end

  it "rejects an encounter linked to an appointment from a different practice" do
    encounter = build(:encounter, practice: practice_a, appointment: create(:appointment, practice: practice_b))

    expect(encounter).not_to be_valid
  end

  it "accepts a clinical note whose patient and author match its encounter practice" do
    encounter = create(:encounter, practice: practice_a)
    note = build(:clinical_note, patient: encounter.patient, encounter: encounter, author: encounter.clinician)

    expect(note).to be_valid
  end

  it "rejects a note with a patient from a sibling practice" do
    encounter = create(:encounter, practice: practice_a)
    note = build(:clinical_note, encounter: encounter, patient: create(:patient, practice: practice_b))

    expect(note).not_to be_valid
  end

  it "rejects a note authored by staff from another medical group" do
    encounter = create(:encounter, practice: practice_a)
    note = build(:clinical_note, encounter: encounter, author: create(:staff_member, practice: other_group_practice))

    expect(note).not_to be_valid
  end
end
