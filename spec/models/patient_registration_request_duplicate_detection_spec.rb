require "rails_helper"

RSpec.describe PatientRegistrationRequest, type: :model do
  describe "#possible_existing_patients" do
    let(:practice) { create(:practice) }
    let(:request_record) do
      described_class.new(practice: practice, first_name: "Arthur",
        last_name: "Evans", date_of_birth: Date.new(1949, 9, 5))
    end

    it "finds matching patients in the same practice despite casing and whitespace" do
      matching = create(:patient, practice: practice,
        first_name: " arthur ", last_name: "EVANS", date_of_birth: Date.new(1949, 9, 5))
      create(:patient, practice: create(:practice),
        first_name: "Arthur", last_name: "Evans", date_of_birth: Date.new(1949, 9, 5))
      create(:patient, practice: practice,
        first_name: "Arthur", last_name: "Evans", date_of_birth: Date.new(1950, 9, 5))

      expect(request_record.possible_existing_patients).to contain_exactly(matching)
    end

    it "does not match with incomplete identifying details" do
      request_record.date_of_birth = nil

      expect(request_record.possible_existing_patients).to be_empty
    end
  end
end
